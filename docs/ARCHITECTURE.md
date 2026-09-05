# Архитектура DuoRoute

## Границы

`lib/duo_route` — единственный источник бизнес-логики. Он использует Ruby stdlib/default gems (`json`, `csv`, `yaml`, `digest`, `time`), не знает об ActiveRecord, HTTP и Rails. На вход получает Ruby Hash/Array, на выходе возвращает `RunResult(decisions, report, manifest)`.

CLI (`DuoRoute::CLI::App`) только разбирает flags, загружает файлы, вызывает `Runner`, проверяет выход и атомарно записывает JSON. Rails-контроллеры только принимают данные, ограничивают upload и создают `RoutingRun`; `RoutingRunJob` вызывает тот же `Runner` и обновляет progress.

## Поток данных

1. `Input::Loader` читает UTF-8 JSON/CSV или YAML через `YAML.safe_load`, ограничивает размер.
2. `Validation::InputValidator` накапливает все нарушения с `path`, `code`, `message`.
3. `Runner` применяет config overrides и, только при явном opt-in, history calibration.
4. `Engine` сортирует операции по `created_at`, сохраняя исходный порядок равных timestamps.
5. `Constraints::Registry` вызывает десять независимых hard checks и сохраняет полную матрицу.
6. `Scorer` через `Policies::Registry` считает projected normalized scores и детерминированно ранжирует pool.
7. `State::Store` ведёт daily/in-progress, финальные count/volume и sliding 60-second RPM.
8. Simulator возвращает `Outcome`; engine выполняет commit/rollback/cascade/fallback.
9. `ReportBuilder` и `RecommendationEngine` строят аналитику и предложения с числовым evidence.
10. `OutputValidator` проверяет обязательный контракт до записи.

## Dependency injection

Engine принимает simulator, constraint registry, progress callback и clock. Scorer принимает registry policies. Это позволяет тестировать сценарии без сети, времени ожидания и случайного выбора маршрута.

## Web persistence

Одна SQLite-таблица `routing_runs` хранит immutable input payloads, config, seed, status/progress и готовые artifacts. Ошибка нового run меняет только его строку. Старые результаты не перезаписываются. Active Job использует in-process `:async` adapter в development; Redis не нужен. Progress endpoint опрашивается Stimulus-контроллером.

## Расширение

Новая hard-проверка реализует `call(provider:, operation:, state:)` и добавляется в `Constraints::Registry::DEFAULTS`. Новая soft policy возвращает `Policies::Score`, регистрируется в `Policies::Registry::TYPES` и включается весом в config. Simulator должен реализовать `call(operation:, provider:, attempt:)`.
