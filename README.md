# DuoRoute

DuoRoute — конкурсное решение команды DuoTech для кейса Hack.Genesis 2026 «Умный роутинг выплат». Оно последовательно обрабатывает очередь, сначала исключает провайдеров по hard constraints, затем ранжирует допустимый пул по настраиваемой комбинации soft policies, моделирует ответ, выполняет cascade/fallback и сохраняет полное объяснение решения.

Если вы впервые открыли проект, начните с [объяснения простыми словами](docs/SIMPLE_GUIDE.md): там описаны смысл системы, основные страницы и пошаговый запуск без финтех-терминов.

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

Откройте <http://localhost:3000>. `bin/setup` устанавливает gems, готовит SQLite и идемпотентно добавляет завершённый public demo run.

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
  --presets balanced,cascade,conversion_first,load_safe
bin/router explain --decisions routing_decisions.json --operation op_103
bin/router generate --scenario stress --operations 10000 --providers 20 \
  --seed 42 --output tmp/generated
```

`--outcomes file.json` включает scripted simulator; без него используется детерминированный seeded simulator. Прогресс больших batch идёт в stderr, JSON не загрязняется. `--quiet` отключает progress/summary.

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

Команда принимает только basename `operations_queue_test.json`, проводит strict validation и пишет атомарно в корень репозитория только `routing_decisions_test.json` и `routing_report_test.json`. Полный регламент: [docs/STOPCODE_CHECKLIST.md](docs/STOPCODE_CHECKLIST.md).

## Presets и policies

- `balanced` — count/volume share, cascade, preferred amount, conversion, load, RPM, turnover и economy;
- `count_share`, `volume_share`, `cascade` — изолированные цели;
- `conversion_first`, `load_safe`, `turnover_commitment`, `economy_first` — готовые бизнес-профили.

Policy registry поддерживает: projected count share, projected volume share, cascade priority, предпочтительный чек, conversion, projected capacity load, RPM intensity, daily turnover min/max и маржинальный запас. Вес и приоритет меняются в YAML/JSON без правки core. Отсутствующее необязательное поле выключает только соответствующую policy.

## Web-консоль

- Dashboard: KPI, target-vs-fact Chart.js, hard/skip reasons, provider capacity, последние runs.
- Новый запуск: upload или ручные JSON/CSV/YAML, preset, timeout mode, simulator и seed; валидация до постановки job.
- Run detail: polling progress без Redis, таблица решений, downloads и rule-based recommendations.
- Operation detail: timeline, hard matrix, ranking/waterfall, conflict/tie-break, state before/after, raw JSON.
- Providers, Strategy Lab, Analytics, Data Generator и Methodology.

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
