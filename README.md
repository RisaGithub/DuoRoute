# DuoRoute

DuoRoute — конкурсное решение команды DuoTech для кейса Hack.Genesis 2026 «Умный роутинг выплат». Оно последовательно обрабатывает очередь, сначала исключает провайдеров по hard constraints, затем ранжирует допустимый пул по настраиваемой комбинации soft policies, моделирует ответ, выполняет cascade/fallback и сохраняет полное объяснение решения.

Два интерфейса используют одно независимое Ruby-ядро из `lib/duo_route`: CLI создаёт конкурсные JSON без базы и сервера; Rails-консоль хранит историю в локальной SQLite и показывает progress, replay, waterfall вкладов, аналитику и скачивание артефактов. Во время маршрутизации сеть не используется.

## Быстрый старт

Требования: Ruby 3.4.x, Bundler 2.6+, SQLite 3. Проект проверен на Ruby 3.4.10 и Rails 8.1.3.1.

```bash
bin/setup --skip-server
bin/router help
bin/router demo --seed 42
ruby script/validate_10.rb routing_decisions.json
bin/rails server
```

Откройте <http://localhost:3000>. Презентация продукта, команды CLI и документация доступны на <http://localhost:3000/about>; кнопка «Запустить web-расчёт» ведёт в форму нового запуска. `bin/setup` устанавливает gems, готовит SQLite и идемпотентно добавляет завершённый public demo run.

## Архитектура

```text
providers + operations + config + history/outcomes
                       │
             Input::Loader + Validator
                       │ errors[] с JSON path / line
                       ▼
                  Ruby Engine
       ┌───────────────┼─────────────────┐
       │               │                 │
 hard constraints  projected policies  State::Store
       │               │             reserve/commit/
       └──── eligible ─┴─ rank ───── rollback + RPM
                       │
                 Simulator contract
                  seeded / scripted
                       │ reject/timeout → next
                       ▼
      decisions + report + reproducibility manifest
              ┌────────┴────────┐
           CLI adapter       Rails job/UI
          JSON files         SQLite history
```

Контроллеры и CLI не содержат альтернативной бизнес-логики. Границы компонентов описаны в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), формулы — в [docs/ALGORITHM.md](docs/ALGORITHM.md).

## CLI

Проверка входа с выводом всех ошибок:

```bash
bin/router validate \
  --providers data/examples/providers.json \
  --operations data/examples/operations_queue_10.json \
  --config config/routing/default.yml
```

Полный запуск:

```bash
bin/router route \
  --providers data/examples/providers.json \
  --operations data/examples/operations_queue_10.json \
  --history data/examples/operations_history.csv \
  --config config/routing/default.yml \
  --preset balanced --seed 42 \
  --decisions routing_decisions.json \
  --report routing_report.json
```

Дополнительные команды:

```bash
bin/router compare --operations data/examples/operations_queue_10.json \
  --presets count_share,cascade,conversion,intensity
bin/router explain --decisions routing_decisions.json --operation op_103
bin/router generate --scenario stress --operations 10000 --providers 20 \
  --seed 42 --output tmp/generated
```

`--outcomes file.json` включает точные ответы scripted; обычный запуск не требует outcomes и по умолчанию использует историю с переходом к snapshot при нехватке данных. Прогресс больших batch идёт в stderr, JSON не загрязняется. `--quiet` отключает progress/summary.

## Stopcode / финальная очередь

Публичная очередь не выдаётся за финальную. Поэтому файлов `routing_decisions_test.json` и `routing_report_test.json` сейчас намеренно нет.

После получения настоящего `operations_queue_test.json`:

```bash
bin/router final \
  --operations operations_queue_test.json \
  --providers data/providers.json \
  --config config/routing/final.yml \
  --preset balanced --seed 42
```

Команда принимает только basename `operations_queue_test.json`, проводит strict validation и пишет атомарно в корень репозитория `routing_decisions_test.json`, `routing_report_test.json` и сопровождающие Config/Manifest. Полный регламент: [docs/STOPCODE_CHECKLIST.md](docs/STOPCODE_CHECKLIST.md).

## Стратегии и параметры

Основных стратегий ровно семь; названия, веса, параметры и примеры загружаются из `config/routing/strategies.yml`:

- `count_share` — доли по количеству (vipay 40%, payflow 35%, quickpay 25%);
- `volume_share` — доли по сумме (vipay 50%, payflow и quickpay по 25%);
- `cascade` — очередь vipay → payflow → quickpay;
- `amount_range` — предпочтительные диапазоны сумм из ТЗ;
- `conversion` — предпочтение более высокой `conversion_24h`;
- `intensity` — число запросов за последние 60 секунд;
- `turnover_commitment` — минимальный и максимальный дневной оборот.

`balanced` называется «Сбалансированная комбинация», `custom` — полностью пользовательский режим. Они позволяют включать факторы, назначать веса и порядок разрешения конфликтов. `load_safe` и `economy` доступны как дополнительные факторы. Старые CLI-профили `conversion_first`, `load_safe`, `economy_first` сохранены для совместимости.

## Web-консоль

- Обзор: только данные выбранного завершённого запуска, KPI, доли количества и суммы, причины исключения, лимиты и рекомендации. Выбор сохраняется в `?run_id=ID`. По умолчанию выбран последний по времени завершения успешный запуск.
- Новый запуск: upload или ручные JSON/CSV/YAML, preset, timeout mode, simulator и seed; валидация до постановки job.
- Run detail: polling progress без Redis, таблица решений, downloads и rule-based recommendations.
- Operation detail: timeline, hard matrix, ranking/waterfall, conflict/tie-break, state before/after, raw JSON.
- Провайдеры, Стратегии и Генератор.

Uploads ограничены 10 МБ, YAML разбирается через `safe_load`, реквизиты фильтруются из Rails logs и телефоны маскируются в UI. Chart.js 4.4.7 хранится локально, CDN и телеметрии нет.

## Форматы

Поддерживаются исходный `providers.json`, JSON-массив операций, optional history CSV, routing YAML/JSON и optional scripted outcomes JSON. Decisions совместимы с публичным enum `attempts.decision = selected|skipped`; отчёт сохраняет поля примера и расширяет их volume distribution, performance, utilization, target exceptions, evidence-based recommendations и SHA-256 manifest. Полные схемы и reason codes: [docs/INPUT_OUTPUT.md](docs/INPUT_OUTPUT.md).

## Проверки

```bash
bin/rails test
RUBOCOP_CACHE_ROOT=/private/tmp/duoroute-rubocop-cache bundle exec rubocop
bundle exec brakeman -q --no-pager
bundle exec bundler-audit check --update
bin/rails zeitwerk:check
bin/rails assets:precompile
```

Тесты проверяют каждое hard-ограничение и границы, policies, tie-break, state transitions, simulator contracts, fallback/timeout, output math, генератор, CLI atomic writes, web-flow и randomized invariants. Публичный валидатор запускается отдельно командой выше.

Сохранённое наблюдение stress run на 10 000 операций × 20 внешних провайдеров находится в [docs/BENCHMARK_10K.json](docs/BENCHMARK_10K.json). Полный audit JSON велик по дизайну; цифры не заявляются как SLA.

## Структура

```text
lib/duo_route/             независимое routing core и CLI
app/                       тонкие Rails adapters и UI
config/routing/            presets, weights, overrides
data/examples/             неизменённые публичные примеры
docs/                      алгоритм, архитектура, допущения, scorecard, demo
test/                      unit, integration, randomized invariants
bin/router                 CLI entrypoint
routing_decisions.json     сгенерированный public demo
routing_report.json        сгенерированный public report
```

Ограничения и спорные трактовки перечислены в [docs/ASSUMPTIONS.md](docs/ASSUMPTIONS.md). Лицензия проекта — MIT; зависимости перечислены в [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Источник симуляции и повторение запуска

`simulation.source` принимает `history`, `provider_snapshot`, `custom`, `scripted`. Обычный режим — `history`: по каждому провайдеру считаются доли approved/rejected/expired среди его строк `operations_history.csv`. Latency берётся из `latency_sec`: `simulation.latency_method=mean` означает среднее, `median` — медиану. Минимальный размер выборки — `simulation.minimum_samples` (по умолчанию 20).

При недостатке истории Approval берётся из `conversion_24h`, Latency — из `avg_latency_sec` snapshot. Остаток `1 − Approval` делится: Expired получает `simulation.failure_expired_share` (по умолчанию 0.2) остатка, Reject — остальное. В `provider_snapshot` этот способ используется сразу. Вероятности задаются долями 0–1, а в интерфейсе проценты отображаются как 0–100%.

В режиме `custom` для каждого провайдера, включая резервный, задайте `simulation.providers.NAME.approved_rate`, `rejected_rate`, `expired_rate`, `average_latency_sec`, `latency_spread_sec`. Сумма трёх вероятностей должна равняться 1. Если задан только Approval, остаток делится по явно указанной `failure_expired_share`. Разброс задаётся в секундах: среднее ± разброс, с ограничением снизу нулём. По умолчанию разброс равен нулю. Для воспроизведения сохраните seed.

`scripted` использует точные ответы из `outcomes.json`, а не вероятности; файл нужен только для такого режима. Можно задать общий `default` или ответы для каждой фактически вызываемой пары операция/провайдер. Проверка покрытия выполняется до запуска. В решениях, попытках и отчёте сохраняется источник симуляции. Для вероятностных режимов дополнительно записываются применённые вероятности, число использованных строк, признак перехода к snapshot и seed.

На «Обзоре» Approval — доля итоговых успешных операций, Latency — средняя сумма времени всех фактических попыток до итогового ответа. На «Провайдерах» Approval и Latency относятся к попыткам конкретного провайдера. Цель берётся из его настроек с применёнными параметрами стратегии; факт считается только по выбранной очереди. История не добавляется в знаменатель распределения.

В выпадающем списке на «Обзоре» или «Провайдерах» выберите запуск — страница обновится автоматически. Прямая ссылка содержит `run_id`. Каждый запуск хранит собственные providers, operations, config, history и outcomes; старые результаты не пересчитываются. Новые метаданные хранятся в существующем JSON-поле конфигурации, изменение схемы БД не требуется. Старые записи без новых метаданных остаются доступны.

В форме нового запуска выбор стратегии подставляет стандартные веса и параметры. Без JavaScript те же значения применяет сервер. Изменения можно внести в YAML/JSON либо по одному `path=value` на строку. Порядок применения: общие значения → стратегия → пользовательский config → точечные изменения → явные поля формы. Веса формы применяются только с флажком переопределения.

Скачайте Config и исходные входные файлы сохранённого Web-запуска, затем повторите через CLI:

```bash
bin/router strategies list
bin/router strategies show count_share
bin/router route --providers providers.json --operations operations.json \
  --history operations_history.csv --config routing_config.json \
  --strategy count_share --seed 42
```

Для scripted добавьте `--outcomes outcomes.json`. Имя стратегии и seed возьмите со страницы запуска. В Config уже сохранены источник, timeout и остальные параметры. SHA-256 в Manifest позволяют проверить совпадение входов; хеши верхнего уровня относятся к каноническому JSON сохранённых данных, а `input_metadata` Web хранит имена загруженных файлов, размер и SHA-256 исходного текста. Временная длительность исполнения не является детерминированной частью отчёта.

CLI поддерживает `--strategy` (и прежний `--preset`), `--config`, `--history`, `--outcomes`, `--simulation-source`, `--seed`, `--timeout-mode`, повторяемый `--set path=value` в route/compare/final. Например:

```bash
bin/router route --strategy count_share \
  --set provider_overrides.vipay.traffic_percentage=50 \
  --set provider_overrides.payflow.traffic_percentage=30 \
  --set provider_overrides.quickpay.traffic_percentage=20
```

CLI сохраняет рядом с отчётом `<report>.config.json` и `<report>.manifest.json`; вся группа артефактов записывается с откатом при ошибке. Compare печатает результаты, итоговые конфигурации и manifests в JSON. Неизвестные настройки, неверные типы и диапазоны отклоняются до записи результатов.
