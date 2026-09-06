# CLI: запуск из терминала

CLI — команды без браузера. Они проверяют данные, выполняют маршрутизацию, сравнивают стратегии, создают демонстрационные данные и формируют финальные файлы без Web и базы данных.

## Оглавление

- [Установка](#installation)
- [Демонстрация](#demo)
- [Входные файлы](#inputs)
- [Все команды](#commands)
- [Стратегии и параметры](#settings)
- [Симуляция](#simulation)
- [Результаты](#outputs)
- [Финальный запуск](#final)
- [Ошибки](#errors)

<a id="installation"></a>
## Требования и установка

Проверенная среда: Ruby **3.4.10**, Bundler 2.6+, SQLite 3 для Web, rbenv для выбора Ruby. Из корня проекта на macOS с установленным Homebrew:

```bash
brew install rbenv ruby-build sqlite
rbenv install -s 3.4.10
rbenv local 3.4.10
eval "$(rbenv init - zsh)"
ruby -v
gem install bundler
bundle install
bin/setup --skip-server
```

На Linux установите rbenv, ruby-build, SQLite и инструменты сборки пакетным менеджером своей системы; остальные команды те же. `bin/setup` готовит и Web-базу с публичным примером. Только для CLI достаточно Ruby и `bundle install`.

Если видна системная Ruby 2.6, проверьте `which ruby` и `rbenv version`. Добавьте `eval "$(rbenv init - zsh)"` в `~/.zshrc`, откройте новый терминал. Немедленный обход: `rbenv exec ruby -v`, `rbenv exec ruby bin/router help`. Версия закреплена в `.ruby-version` и Gemfile. `bin/router` и `bin/setup` проверяют её до загрузки приложения и при несовпадении завершаются короткой ошибкой. Все дальнейшие команды предполагают Ruby 3.4.10.

<a id="demo"></a>
## Быстрый демонстрационный запуск

```bash
bin/setup --skip-server
bin/router demo --seed 42
ruby script/validate_10.rb routing_decisions.json
```

Создаются или заменяются `routing_decisions.json`, `routing_report.json`, `routing_report.json.config.json`, `routing_report.json.manifest.json` в корне. Команда `demo` использует публичные 10 операций, историю и **точные ответы** из `data/examples/demo_outcomes.json`. Это демонстрация формата и переходов, а не прогноз успешности и не финальный результат. Для вероятностного примера используйте `route` или `demo --simulation-source history`.

<a id="inputs"></a>
## Входные файлы

Пути в примерах реальны и отсчитываются от корня проекта. Ошибка входа возвращает код завершения 2, список `path`, `code`, `message`; результаты маршрутизации не записываются. Ограничение CLI — 128 MiB на входной файл, кодировка UTF-8.

| Файл | Обязательность и назначение | Основные поля | Пример проверки | При ошибке |
|---|---|---|---|---|
| `providers.json` | Обязателен; снимок состояния до очереди. Обычно `data/examples/providers.json`, для финала `data/providers.json` | Объект `snapshot_at`, `gateway`, `merchant`, `providers[]`. У провайдера `payment_system`, `status`, `traffic_percentage`, сумма и дневные лимиты, `in_progress_*`, `banks`, `exclude_banks`, маржа, `available_requisites`, `conversion_24h`, `avg_latency_sec` | `bin/router validate --providers data/providers.json` | Неверные типы, дубли имени, отсутствующий резервный провайдер и несогласованные доли отклоняются |
| Очередь операций | Обязательна; публичная — `data/examples/operations_queue_10.json` | Массив: уникальный `operation_id`, `created_at` ISO-8601 с часовым поясом, положительное число `amount`, непустой `bank`; `payout_requisite` сохраняется как вход | `bin/router validate --operations data/examples/operations_queue_10.json` | Пустая очередь, дубли, дата раньше снимка, плохая сумма отклоняются |
| `operations_history.csv` | Необязательна для обычного расчёта; нужна непустая для `final` с источником `history`. Обычный CLI автоматически читает `data/operations_history.csv`, если он есть | Заголовок `operation_id,created_at,amount,bank,card_brand,payment_system,status,latency_sec` | `bin/router validate --history data/operations_history.csv` | Неверные колонки, дубли ID, неизвестный провайдер/статус, отрицательное время отклоняются; малая выборка даёт явный переход к снимку |
| Конфигурация | Загружается всегда; стандартная `config/routing/default.yml`, финальная `config/routing/final.yml`. YAML или JSON | `routing`, `simulation`, `calibration`, `provider_overrides`, `presets.NAME.weights`, `policy_priorities`, `seed` | `bin/router validate --config config/routing/default.yml` | Неизвестные ключи, типы, отрицательные веса, все веса 0, небезопасный YAML отклоняются |
| `outcomes.json` | Только для `scripted`, точных ответов вместо вероятностей | `outcomes` с ключами `operation_id:payment_system`, `result`, `latency_sec`; общий `default`; необязательные поля проверки позднего статуса | `bin/router validate --outcomes data/examples/demo_outcomes.json` | Неверный ответ или непокрытая пара операция/провайдер отклоняются до расчёта |

Дополнительные поля провайдера: `volume_share_pct`, `priority`, `preferred_amount_min/max`, `requests_per_minute_limit`, `daily_turnover_min/max`. Их можно задавать в JSON или через `provider_overrides`. Числовой лимит `null` означает отсутствие ограничения; доступные реквизиты должны быть целым числом. Точные условия — в [алгоритме](ALGORITHM.md#constraints).

Пример точного сценария:

```json
{"outcomes":{"op_1:vipay":{"result":"rejected","latency_sec":18}},"default":{"result":"approved","latency_sec":24}}
```

`reference_decisions.json` нужен только публичному валидатору, **не является входом роутера**. Файлы примеров не заменяют будущую финальную очередь.

<a id="commands"></a>
## Все CLI-команды

Общий синтаксис: `bin/router COMMAND [OPTIONS]`. `bin/router help` выводит список; `--help` есть у validate/route/demo/final/generate/compare/explain. `strategies` требует `list` или `show NAME`; `evaluate-default` параметров не принимает.

В таблице «общие параметры» означает `--providers`, `--operations`, `--history`, `--config`, `--outcomes`, `--strategy` (или `--preset`), `--simulation-source`, `--timeout-mode`, повторяемый `--set`, `--seed`, `--quiet`.

| Команда и синтаксис | Назначение, параметры и пример | Выход | Ошибки |
|---|---|---|---|
| `strategies list` | Каталог семи стратегий: `bin/router strategies list` | JSON в стандартный вывод; файлов нет | Лишние аргументы |
| `strategies show NAME` | Стандартные параметры: `bin/router strategies show count_share` | JSON одной стратегии; файлов нет | Неизвестное имя; balanced/custom не входят в каталог семи |
| `validate [OPTIONS]` | Предварительная проверка, общие параметры: `bin/router validate --config config/routing/default.yml` | JSON со статусом, количеством входов; файлов нет | Ошибки входа/конфигурации; это не полный расчёт |
| `route [OPTIONS]` | Маршрутизация; общие параметры плюс `--decisions PATH --report PATH`: `bin/router route --strategy conversion --seed 42` | Decisions, report и два служебных JSON | Ошибки входа, недоступный fallback, ошибка вывода |
| `demo [OPTIONS]` | Публичный точный сценарий; общие параметры и два пути результата: `bin/router demo --seed 42` | Четыре публичных JSON | Те же проверки, что route |
| `final [OPTIONS]` | Настоящая финальная очередь; общие параметры плюс `--dry-run --explain-summary`: `bin/router final --dry-run --explain-summary` | См. [финальный запуск](#final); пути результата фиксированы | Неверное имя, отсутствующая очередь/история, ошибки диска/данных |
| `generate [OPTIONS]` | Данные: `bin/router generate --scenario stress --operations 10000 --providers 20 --seed 42 --output tmp/generated` | В каталоге `providers.json`, `operations.json`, `outcomes.json`, `history.csv`, `manifest.json` | Неизвестный сценарий, неположительные размеры, ошибка записи |
| `compare [OPTIONS]` | Общие параметры плюс `--presets LIST`: `bin/router compare --presets count_share,cascade,conversion --seed 42` | JSON сравнения, конфигураций и Manifest в стандартный вывод | Ошибки любого запуска/стратегии |
| `explain --operation ID [--decisions PATH]` | Разбор сохранённой операции: `bin/router explain --decisions routing_decisions.json --operation op_105` | JSON операции; файлов нет | Нет ID, операция не найдена, файл не читается |
| `evaluate-default` | `bin/router evaluate-default`: фиксированное сравнение шести кандидатов, 258 прогонов | Машиночитаемый отчёт в каталоге свидетельств; описание в [критериях](CRITERIA_COMPLIANCE.md#default) | Любые параметры, ошибка расчёта/записи |

`compare` по умолчанию сравнивает семь стратегий с новым исходным состоянием на каждую. Явный `--strategy`/`--preset` заменяет список одним режимом; для нескольких нужен `--presets`. Чтобы сохранить вывод: `bin/router compare --presets count_share,conversion > tmp/comparison.json` (каталог `tmp` должен существовать). Прогресс больших очередей идёт в stderr; `--quiet` отключает прогресс и краткий итог.

<a id="settings"></a>
## Стратегии и параметры

Числа в следующей таблице — примеры для явной настройки, а не автоматически добавляемые цели.

Стратегия — правило предпочтения среди допустимых провайдеров. Ни один вес не отменяет обязательных ограничений.

| Стратегия | Смысл | Основные параметры |
|---|---|---|
| `count_share` | Доля по числу операций | `traffic_percentage`: vipay 40%, payflow 35%, quickpay 25% |
| `volume_share` | Доля по сумме | `volume_share_pct`: 50/25/25% |
| `cascade` | Очерёдность | `priority`: меньшее число раньше |
| `amount_range` | Предпочтительный диапазон суммы | `preferred_amount_min/max`; фактор называется `preferred_amount` |
| `conversion` | Более высокая ожидаемая успешность | `conversion_24h`, доля 0–1 |
| `intensity` | Запас запросов в минуту | `requests_per_minute_limit` и текущие реальные вызовы |
| `turnover_commitment` | Достижение дневного оборота | `daily_turnover_min/max`; мягкая цель, отдельно от дневного жёсткого лимита |

`balanced` — готовая комбинация: conversion 4; count_share, volume_share, load_safe, intensity, turnover_commitment по 2; latency 1; economy 0.5. `custom` позволяет задать собственные веса. Дополнительные факторы: загрузка `load_safe`, время ответа `latency`, запас маржи `economy`. Это не дополнительные самостоятельные стратегии. Старые профили `conversion_first`, `load_safe`, `economy_first` сохранены для совместимости.

`--strategy` выбирает режим, `--preset` — его синоним. `--config` читает YAML/JSON, `--set path=value` меняет отдельный ключ. Порядок: общие настройки → веса стратегии → пользовательская конфигурация → точечные изменения; явный seed передаётся отдельно. Последнее изменение одного пути побеждает. Неизвестные настройки отклоняются.

Обычная стратегия:

```bash
bin/router route --strategy count_share --seed 42 \
  --set provider_overrides.vipay.traffic_percentage=50 \
  --set provider_overrides.payflow.traffic_percentage=30 \
  --set provider_overrides.quickpay.traffic_percentage=20
```

Комбинация с усилением конверсии:

```bash
bin/router route --strategy balanced --seed 42 \
  --set presets.balanced.weights.conversion=5 \
  --simulation-source history --timeout-mode fallback_on_timeout
```

Пользовательская настройка с отключением остальных факторов:

```bash
bin/router route --strategy custom --config config/routing/default.yml --seed 42 \
  --set 'presets.custom.weights={count_share: 2, conversion: 4}' \
  --set 'presets.custom.policy_priorities=[conversion, count_share]'
```

Веса неотрицательны; хотя бы один положителен. 0 полностью отключает фактор, включая выбор при равенстве. Доли количества внешних провайдеров должны давать 100%; резерв в эту настройку не входит. Формулы и правило равенства — в [алгоритме](ALGORITHM.md).

### Импорт и экспорт конфигурации

Отдельных команд `import` и `export` нет. Импорт выполняется через `--config PATH`; результаты экспортируются через `--decisions PATH` и `--report PATH`. Рядом с отчётом сохраняются разрешённая конфигурация `<report>.config.json` и Manifest `<report>.manifest.json`.

Для повторения используйте те же входы, seed и версию ядра, передав сохранённый Config в `--config`. Web скачивает тот же формат через «Config», а форма нового запуска принимает его в поле «Config YAML / JSON». Пользовательские веса задаются в `presets.custom.weights` и используют только зарегистрированные soft policies.

<a id="simulation"></a>
## Симуляция ответов

Реальных API провайдеров нет. Симуляция позволяет проверить успех, отказ и переходы, не отправляя выплаты. `approved` — успех, `rejected` — отказ, `expired` — время ожидания истекло. Latency — время ответа в секундах.

| `--simulation-source` | Ответ и время |
|---|---|
| `history` | Доли статусов из завершённых строк истории до времени снимка; время — среднее (`mean`) или медиана (`median`) `latency_sec` |
| `provider_snapshot` | Успех из `conversion_24h`, время из `avg_latency_sec`; история не задаёт вероятности |
| `custom` | Явные `simulation.providers.NAME.approved_rate`, `rejected_rate`, `expired_rate`, `average_latency_sec`, `latency_spread_sec`, включая spacepayments |
| `scripted` | Точные ответы из `--outcomes`, без случайного выбора; допускается общий `default` |

Порог истории — `simulation.minimum_samples=20` на провайдера. Ниже порога используется снимок, что фиксируется в Manifest. Остаток после вероятности успеха делится: `failure_expired_share=0.2` остатка на expired, остальное на rejected. Старое поле `simulation.expired_rate` поддерживается как абсолютная доля expired, ограниченная остатком; для новых настроек используйте `failure_expired_share`.

В `custom` сумма трёх вероятностей равна 1. Если задан только успех, укажите `failure_expired_share` для деления остатка. Среднее время и разброс неотрицательны: среднее ± разброс, минимум 0; стандартный разброс 0. Вероятностное время округляется до целых секунд; scripted допускает дробные секунды.

`--outcomes` обычно включает scripted автоматически. Явный `--simulation-source history`, `provider_snapshot` или `custom` исключает outcomes из расчёта. Для демонстрации переходов используйте scripted; для оценки стратегии — фиксированные данные и одинаковые seed. Seed — неотрицательное целое, фиксирующее моделируемые ответы. **Не подбирайте seed ради красивого результата:** это меняет условия сравнения, а не улучшает правило маршрутизации.

`--timeout-mode fallback_on_timeout` освобождает резерв и продолжает попытки. `hold_until_status` удерживает ёмкость до синхронной проверки статуса; неизвестный статус оставляет expired и резерв. Это модель, а не реальное ожидание сетевого события.

<a id="outputs"></a>
## Результаты

| Файл | Содержимое |
|---|---|
| `routing_decisions.json` | Массив: одно решение на каждый входной ID, в хронологическом порядке |
| `routing_report.json` | Итоги всей очереди, доли, причины исключений, лимиты, рекомендации |
| `<report>.config.json` | Итоговая конфигурация после всех изменений |
| `<report>.manifest.json` | SHA-256 входов и конфигурации, seed, версии, источники симуляции, отсечение истории, сведения для повторения |

В решении обязательны по ТЗ `operation_id`, `selected_provider`, `attempts` с `provider`, `decision`, `reason`, `simulated_result`. `decision` принимает только `selected` или `skipped`; ровно один selected означает итоговый маршрут, не гарантированный успех. Результат принимает только `approved`, `rejected`, `expired`. `latency_sec` есть в примере ТЗ и обязателен во внутренней проверке DuoRoute; это сумма времени всех реальных попыток.

Дополнения DuoRoute: `strategy`, `score`, `score_breakdown` (вес и вклад цели), `eligible_pool`, `ranking`, `constraint_matrix`, `conflicts`, `tie_break_rule`, `state_before`, `state_after`, `fallback_used`, `status_check_result`, `decision_time_ms`. Попытки сохраняют ответ, последовательность, время и источник симуляции; skipped может обозначать запрет, более низкую оценку или уже состоявшийся неуспешный вызов.

Все коды причин определены в [reason_codes.rb](../lib/duo_route/reason_codes.rb). Обязательные отказы перечислены в [карте ограничений](CRITERIA_COMPLIANCE.md#constraints); причины процесса включают `lower_combined_score`, `provider_rejected`, `provider_expired`, `provider_expired_status_rejected`, `highest_combined_score`, `timeout_held_until_status`, `external_pool_exhausted`.

Совместимые поля отчёта: `period`, `total_operations`, `distribution`, `skip_reasons`, `projected_daily_utilization`, `recommendations` (массив строк). Использование дневного лимита содержит `used`, `limit`, `utilization_pct` и совместимые имена `daily_used`, `daily_limit`, `daily_utilization_pct`.

Дополнения: `total_amount`, `volume_distribution`, отклонение `deviation_pp` в процентных пунктах, итоговые статусы, Approval/Fallback/Latency, `provider_performance`, `capacity_utilization`, `turnover_commitments`, `target_exceptions`, `history_analytics`, `recommendation_details`, `daily_state_history`, `daily_state_date`. Доли относятся только к итоговому провайдеру текущей очереди, включая неуспешные результаты; история не увеличивает знаменатель.

Повторение Web-расчёта: скачайте Providers, Operations, History, Config, Manifest и при scripted Outcomes. Подставьте сохранённые имя стратегии и seed:

```bash
bin/router route --providers providers.json --operations operations.json \
  --history operations_history.csv --config routing_config.json \
  --strategy balanced --seed 42
```

Для scripted добавьте `--outcomes outcomes.json`. SHA-256 верхнего уровня относится к каноническим сохранённым данным; Web `input_metadata` хранит также имя, размер и хеш исходного текста. Время исполнения отчёта не детерминировано, сами решения воспроизводимы при одинаковых входах, настройках, seed и версии ядра.

<a id="final"></a>
## Финальный запуск — только после получения очереди

**Для `final` требуется входной файл `operations_queue_test.json`.** Публичный пример не заменяет финальную очередь. Если файла нет, `bin/router final`, в том числе с `--dry-run`, возвращает `file_not_found`, exit 2.

После получения настоящего файла:

1. Положите `operations_queue_test.json` в корень проекта.
2. Сверьте `data/providers.json` с выданным снимком провайдеров.
3. Сверьте `data/operations_history.csv` с выданной историей. При источнике `history` пустая или отсутствующая история останавливает final.
4. Выполните полный расчёт и проверку временных JSON без записи финальных файлов:

   ```bash
   bin/router final --dry-run
   bin/router final --dry-run --explain-summary
   ```

5. После успешной проверки сформируйте результат:

   ```bash
   bin/router final
   ```

   Для записи с подробным выводом можно вместо этого выполнить `bin/router final --explain-summary`. **Сам по себе `--explain-summary` не запрещает запись.**

6. Проверьте оба JSON, количество и ID, рекомендации, источники симуляции и контрольные суммы:

   ```bash
   ruby -rjson -e 'q=JSON.parse(File.read("operations_queue_test.json")); d=JSON.parse(File.read("routing_decisions_test.json")); r=JSON.parse(File.read("routing_report_test.json")); abort "coverage mismatch" unless q.map{|x|x["operation_id"]}.sort == d.map{|x|x["operation_id"]}.sort && r["total_operations"] == q.size; puts "coverage ok: #{d.size}"'
   git diff --check
   ```

7. Запустите выданный **финальный валидатор организаторов** по его инструкции. Его команда пока неизвестна. `script/validate_10.rb` проверяет публичные 10 ID и не подходит для новой очереди.
8. Команда проекта должна закоммитить и отправить результаты в корень главного репозитория в ветке `main`. До получения очереди этот шаг для финальных результатов не выполняется.

Стандарт final: очередь в корне, `data/providers.json`, `data/operations_history.csv`, `config/routing/final.yml`, balanced, seed 42, history, `fallback_on_timeout`. Явный `--simulation-source provider_snapshot` разрешает работу без истории, но меняет условия; его нужно отразить при сдаче.

Защита: проверяется точное имя очереди, отсутствие пересечения путей входа и выхода (в том числе symlink/hardlink), доступность каталога и свободное место. Сначала проверяется вход, затем весь результат и сериализованные временные JSON. Обычная ошибка не оставляет частичного нового результата; предыдущие файлы восстанавливаются при ошибке замены. Запись защищена блокировкой и атомарной заменой каждого файла.

В корне создаются ровно два конкурсных файла: `routing_decisions_test.json` и `routing_report_test.json`. Служебные `config.json`, `manifest.json` и файл блокировки находятся в `tmp/final_audit`. Dry-run использует удаляемый временный каталог. Одновременная атомарность двух имён при отключении питания не гарантируется: повторите final на тех же входах и проверьте пару; подробнее [ограничения](CRITERIA_COMPLIANCE.md#limitations).

<a id="errors"></a>
## Ошибки и решение проблем

| Ошибка | Что сделать |
|---|---|
| Ruby 2.6 / несовместимые gems | Активировать rbenv, проверить `ruby -v`, повторить `bundle install` |
| `file_not_found` | Проверить путь и рабочий каталог; для финала дождаться настоящей очереди |
| `malformed_json/yaml/csv`, `invalid_encoding` | Исправить формат/UTF-8 по указанному пути или строке |
| `invalid_csv_headers`, `csv_column_count` | Восстановить заголовок и число полей каждой строки |
| `duplicate_operation_id`, `duplicate_payment_system` | Исправить дубли во входах |
| `invalid_configuration`, `zero_weights` | Сверить имя стратегии, ключи, типы, сумму вероятностей и положительный вес |
| `traffic_share_sum` | Проверить сумму долей количества внешних провайдеров, не нормализовать молча |
| `before_snapshot`, `invalid_iso8601` | Проверить дату снимка и ISO-8601 с Z/offset |
| `unsupported_precision` | Проверить точность денежных чисел; программа не округляет их молча |
| `fallback_missing/unavailable` | Проверить spacepayments и его обязательные ограничения |
| `file_too_large` | CLI: 128 MiB; Web: 10 MiB на поле/файл |
| Недостаточно места / пересечение путей / блокировка | Освободить место, выбрать отдельные выходы, дождаться другого писателя |
| Нет операции в `explain` | Проверить ID и файл decisions нужного запуска |


<a id="readiness"></a>
## Проверка готовности и репетиция

`readiness` включает `ruby script/check_production_docs.rb`: проверку пользовательских текстов и локальных файловых ссылок. Отдельная проверка Markdown также проверяет якоря.

```bash
bin/router readiness
bin/router readiness --full
bin/router rehearse-final
bin/router rehearse-final --operations data/operations_queue_10.json \
  --providers data/providers.json --history data/operations_history.csv
```

Обычный readiness занимает около секунды на проверенной машине: Ruby 3.4.10, обязательные файлы, config, семь стратегий, providers/history, два demo во временном каталоге, внутренний и независимый аудит, публичный валидатор, шесть схем, Markdown-ссылки, отсутствие преждевременных финальных файлов и Git без содержимого файлов. Изменённое рабочее дерево разрешено; конфликты Git запрещены. `READY` означает exit 0, `NOT READY` — exit 2 со списком причин. Это режим **до получения финальной очереди**: наличие любого из трёх финальных файлов считается проблемой.

`--full` добавляет Rails tests, RuboCop, Brakeman, локальный bundler-audit без обновления базы и Zeitwerk. Сеть не нужна; тесты могут изменять тестовую SQLite, кэш и логи. Assets и benchmark остаются отдельными явными проверками, чтобы команда не меняла выдачу работающего сервера.

**Strict по умолчанию:** `bin/router rehearse-final` возвращает exit 2 при любой обязательной ошибке, включая reference mismatch. Разрешить только объяснённое статическое расхождение: `bin/router rehearse-final --allow-reference-mismatch`. Тогда успешный статус — `PASS WITH REFERENCE MISMATCH` (exit 0), а не `REHEARSAL PASS`. Падение схемы, semantic audit, согласованности или другая ошибка публичного валидатора флагом не разрешаются. Аналогичный флаг поддерживает `final`; все применимые проверки выполняются до публикации.

Rehearsal копирует только указанную очередь в `Dir.mktmpdir`, присваивает ей там конкурсное имя, дважды вызывает `CLI::App final` с временным root и теми же опциями. Внутренний и независимый валидаторы проверяют временные результаты; decisions совпадают побайтово, report — после исключения только `reproducibility.duration_ms`. Весь временный каталог удаляется и при ошибке. В корне проекта `_test`-файлы не создаются.

Публичный валидатор запускается только на совпадающих публичных queue/providers. На вероятностном final seed 42 он сообщает один конфликт: op_108 может перейти к spacepayments после отказа quickpay, хотя эталон требует quickpay. Этот результат показывается целиком и блокирует публикацию без явного разрешения. Обёртка сопоставляет каждую ошибку с reference и реально состоявшимся отказом первоначального кандидата; ID и провайдеры не зашиты в исключение. Для другой очереди public validator помечается N/A. Скрипт организаторов не изменяется; seed не подбирается.

<a id="independent-audit"></a>
## Независимый аудит и схемы

```bash
ruby script/audit_submission.rb \
  --providers data/providers.json --operations data/operations_queue_10.json \
  --decisions routing_decisions.json --report routing_report.json
ruby script/check_schemas.rb schemas/routing_decisions.schema.json routing_decisions.json
bin/router feasibility --report routing_report.json
```

Аудитор — отдельный stdlib Ruby-скрипт без Rails, базы, Engine и проектных валидаторов. Он не пишет файлы. Проверяет корни JSON, повторные JSON-ключи/ID, покрытие и порядок, провайдеров, enum, попытки и selected, latency, fallback, десять ограничений, дневной оборот, in-progress, RPM, UTC-дни, commit/rollback и сводку отчёта. Проверяет доступные state_before/state_after, дневную историю и числовые поля goal_feasibility. Ошибка: `AUDIT FAIL`, exit 2; полный успех в объявленной области: `AUDIT PASS`, exit 0.

`--config routing_report.json.config.json` закрепляет **разрешённую JSON-конфигурацию**, а не исходный YAML с неполными настройками. Без этой опции конфигурация берётся из Manifest; контрольные суммы подтверждают согласованность, но не аутентичность. Сокращённые decisions должны сохранить result/latency/status_check_result фактических attempts для восстановления состояния. Исторический RPM, реальные внешние завершения, истинность ответов, оптимальность score и произвольные секреты внутри текста доказать по результату нельзя. Проверка чувствительных имён полей эвристическая, без вывода значений.

`final`, включая dry-run, запускает независимый аудит **на staged-файлах до rename**; провал сохраняет прежнюю пару. Самостоятельная команда полезна для проверки скачанных или вручную перенесённых файлов. Формальные [схемы](../schemas) описывают структуру; межполевые условия и состояние требуют семантических валидаторов. `check_schemas.rb` поддерживает только используемые в репозитории ключевые слова схем и отклоняет неизвестные; это не универсальная реализация стандарта.

## Детализация аудита

`route --audit-level full|submission|compact`; final по умолчанию использует `submission`, обычные CLI/Web — `full`. Алгоритм выбора общий. Full сохраняет все проверки и вклад каждого кандидата. Submission сохраняет attempts со всеми причинами, все hard failures, eligibility, краткий ranking, выбранный score_breakdown и state до/после; успешные checks не повторяются, simulation profiles хранятся в report/Manifest. Compact дополнительно опускает снимки состояния отдельных операций. `audit_level` указан в Manifest. Для подробного финального аудита можно явно выбрать `--audit-level full`; автоматической второй полной копии нет.

`evaluate-default` выполняет 258 прогонов комбинаций, 2 064 проверки чувствительности и 672 сравнения семи стратегий с balanced; занимает несколько минут. Команда обновляет только артефакт исследования, **не меняет веса config** и не читает финальную очередь.


## Применимые цели и честное сравнение

Каталог содержит примеры параметров. Ядро и CLI не подмешивают их в providers: изменение стратегии меняет веса, а цели и лимиты берутся только из входа, config и `--set`. Для заданной явно цели объёма 0 отклонение рассчитывается; отсутствие поля или null исключает цель. `compare` возвращает `volume_absolute_deviation_pp: null`, если целей нет, и `volume_target_providers: []`. При частичных целях суммируются абсолютные отклонения только перечисленных провайдеров, без деления на два или нормализации неполной суммы. Аналогичный список есть для count targets.

`selected_provider` — итоговый провайдер после каскада. Первоначальный кандидат — первая реальная попытка с `result`, а не первая строка attempts: перед вызовами могут находиться записи hard exclusions. Attempts сохраняет все вызовы, ответы, причины переходов и исключения. После исчерпания внешних кандидатов fallback становится итоговым провайдером, а report относит операцию к нему.

Default — `balanced`, версия `paired-final-v1-2026-09-06`. Balanced — единственный проверенный статический кандидат с worst-case regret успешности не выше 0,1 п.п. и на validation, и на holdout. Кандидат `amount_range` имеет больший worst-case regret на holdout. Глобальная оптимальность не доказана. Краткие метрики и веса — в [записи default](../config/routing/default_selection.json).

### Версия и доказательства default

`routing.default_strategy` в default.yml/final.yml и `config/routing/default_selection.json` согласованы. CLI, Web и Runner используют эти настройки. `--strategy` явно выбирает другой режим. В Manifest и Report сохраняются `strategy_selection`: фактическая стратегия, веса, policy_priorities, причина, версия и основные validation/holdout-метрики. Seed и хеши входов находятся рядом в reproducibility. Пользовательские настройки отмечены отдельно; исследование default не доказывает их превосходства.

Повторение исследования: `ruby script/evaluate_default_final.rb tmp/repeated-study.json`. Команда не меняет рабочие веса и не использует финальную очередь. `ruby script/replay_default_final.rb tmp/repeated-study.json` сверяет решения по всем сценариям в обратном порядке.
