# Соответствие критериям

DuoRoute реализует последовательный выбор провайдера: обязательные ограничения, семь стратегий и их комбинации, повторные попытки, резервный маршрут, объяснение и отчёт. Ниже — карта для проверки, а не присвоенные себе баллы.

Код ядра — [lib/duo_route](../lib/duo_route), Web — [app](../app), команды — [CLI::App](../lib/duo_route/cli/app.rb). Проверяйте входы, матрицу ограничений, переходы и согласованность итогового JSON.

После установки Ruby 3.4.10 через rbenv:

```bash
bin/setup --skip-server
bin/dev -b 127.0.0.1 -p 3000
```

Web: <http://localhost:3000>. CLI в другом терминале:

```bash
bin/router demo --seed 42
ruby script/validate_10.rb routing_decisions.json
bin/router explain --operation op_105
```

Публичный результат: `routing_decisions.json`, `routing_report.json` и служебные Config/Manifest. Финальные `routing_decisions_test.json` и `routing_report_test.json` **намеренно отсутствуют**, потому что настоящая очередь ещё не получена. Публичные примеры не являются финальным результатом. Полные инструкции — [CLI](CLI.md) и [Web](WEB.md).

## Оглавление

- [Карта реализации](#map)
- [Точные критерии и баллы](#criteria)
- [Экспертная оценка](#experts)
- [Техническая оценка](#technical)
- [Отраслевая оценка](#industry)
- [Обязательные файлы](#files)
- [Обязательные ограничения](#constraints)
- [Стратегии и конфликты](#strategies)
- [Каскад и резерв](#cascade)
- [Пограничные ситуации](#edges)
- [Обоснование default](#default)
- [Повторные проверки и benchmark](#verification)
- [Безопасность](#security)
- [Честные ограничения](#limitations)

<a id="map"></a>
## Карта реализации

Термины: hard constraints — обязательные ограничения; soft goals — цели предпочтения; score — оценка; projected — состояние с учётом новой операции; snapshot — исходный снимок. Reserve/commit/rollback — резервирование, фиксация успеха и освобождение резерва. RPM — число запросов за минуту; latency — время ответа; fallback — резервный маршрут. Audit trail — полное объяснение решения; Manifest — параметры и контрольные суммы запуска. Benchmark — замер производительности, baseline — отправная конфигурация, training/holdout — набор выбора и отдельный проверочный набор.

Каждый подпункт оценки ниже ссылается на конкретную строку этой карты. В ней собраны код, команда, экран, тест и поле результата без повторения длинных путей.

| Требование | Как реализовано | Код | Web | CLI | Тест или доказательство |
|---|---|---|---|---|---|
| <a id="proof-1"></a>1. Ограничения | 10 обязательных проверок, затем оценка по активным мягким целям; ни один вес не отменяет отказ. JSON: `constraint_matrix; attempts.reason` | [constraints/registry.rb](../lib/duo_route/constraints/registry.rb) | Операция: матрица ограничений | `bin/router explain --operation op_103` | [constraints_test.rb](../test/duo_route/constraints_test.rb) |
| <a id="proof-2"></a>2. Каскад и fallback | Резерв → ответ → фиксация/откат → следующий; spacepayments после внешних. JSON: `attempts; fallback_used; simulated_result` | [engine.rb](../lib/duo_route/engine.rb) | Операция op_101: попытки | `bin/router demo --seed 42` | [engine_test.rb](../test/duo_route/engine_test.rb) |
| <a id="proof-3"></a>3. Семь стратегий | Семь стратегий и нормированные оценки допустимого пула. JSON: `score_breakdown; ranking` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегии; операция: вклад целей | `bin/router route --strategy balanced --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-4"></a>4. Комбинация целей | Взвешенная сумма оценок активных факторов. JSON: `score; score_breakdown` | [scorer.rb](../lib/duo_route/scorer.rb) | Новый запуск: веса; операция: вклад | `bin/router route --strategy balanced --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-5"></a>5. Настройки | YAML/JSON, provider_overrides и path=value без изменения формул. JSON: `manifest.resolved_configuration` | [configuration.rb](../lib/duo_route/configuration.rb) | Новый запуск; сохранение параметров стратегий | `bin/router validate --config config/routing/default.yml` | [configuration_test.rb](../test/duo_route/configuration_test.rb) |
| <a id="proof-6"></a>6. Причина выбора | Итоговый рейтинг, причина и вклад целей. JSON: `selected_provider; score_breakdown; attempts.reason` | [engine.rb](../lib/duo_route/engine.rb) | Операция: причина выбора | `bin/router explain --operation op_105` | [engine_test.rb](../test/duo_route/engine_test.rb) |
| <a id="proof-7"></a>7. Причины исключения | Полная матрица, реальные значения и границы каждого отказа. JSON: `constraint_matrix; attempts.reason` | [constraints/registry.rb](../lib/duo_route/constraints/registry.rb) | Операция: причины исключений | `bin/router explain --operation op_103` | [constraints_test.rb](../test/duo_route/constraints_test.rb) |
| <a id="proof-8"></a>8. Архитектура | Независимый Runner; CLI и Rails — адаптеры; реестры правил. JSON: `manifest; структура кода (не отдельное поле JSON)` | [runner.rb](../lib/duo_route/runner.rb) | О продукте; Web вызывает то же ядро | `bin/rails zeitwerk:check` | [backend_audit_test.rb](../test/duo_route/backend_audit_test.rb) |
| <a id="proof-9"></a>9. Читаемость | Имена компонентов отражают назначение; руководства с командами. JSON: `Читаемость оценивается по коду, отдельного поля нет` | [engine.rb](../lib/duo_route/engine.rb) | О продукте: документация | `bundle exec rubocop` | [cli_test.rb](../test/duo_route/cli_test.rb) |
| <a id="proof-10"></a>10. Ошибки | Ошибки с путём/кодом; строгая проверка до записи, откат файлов. JSON: `Ошибки stderr: errors[].path/code/message; при ошибке результата нет` | [validation/input_validator.rb](../lib/duo_route/validation/input_validator.rb) | Новый запуск: ошибки; генератор invalid_data | `bin/router validate` | [backend_audit_test.rb](../test/duo_route/backend_audit_test.rb) |
| <a id="proof-11"></a>11. Распределение | Факт, цель и отклонение количества/суммы по итоговому маршруту. JSON: `distribution; volume_distribution; deviation_pp` | [reporting/report_builder.rb](../lib/duo_route/reporting/report_builder.rb) | Обзор: цель и факт | `bin/router demo --seed 42` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-12"></a>12. Успешность и история | Успех, отказы, время попыток, ёмкость и история. JSON: `provider_performance; capacity_utilization; history_analytics` | [reporting/history_analyzer.rb](../lib/duo_route/reporting/history_analyzer.rb) | Провайдеры; Обзор | `bin/router route --history data/operations_history.csv --seed 42` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-13"></a>13. Рекомендации | Правила с числовым основанием и конкретным изменяемым параметром. JSON: `recommendations; recommendation_details` | [reporting/recommendation_engine.rb](../lib/duo_route/reporting/recommendation_engine.rb) | Запуск: рекомендации; Обзор | `bin/router demo --seed 42` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-14"></a>14. Состояние | Принадлежащие Engine резервы, точные суммы, UTC-дни, окно RPM. JSON: `state_before; state_after; daily_state_history` | [state/store.rb](../lib/duo_route/state/store.rb) | Операция: state до/после | `bin/router explain --operation op_105` | [state_test.rb](../test/duo_route/state_test.rb) |
| <a id="proof-15"></a>15. Количество | Projected доля числа операций против traffic_percentage. JSON: `score_breakdown.count_share; distribution` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегия count_share; Обзор | `bin/router route --strategy count_share --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-16"></a>16. Объём | Projected доля суммы против volume_share_pct. JSON: `score_breakdown.volume_share; volume_distribution` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегия volume_share; Обзор | `bin/router route --strategy volume_share --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-17"></a>17. Приоритет | Нормированный priority задаёт предпочтение в допустимом пуле. JSON: `score_breakdown.cascade` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегия cascade; операция: рейтинг | `bin/router route --strategy cascade --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-18"></a>18. Диапазон суммы | Предпочтительный диапазон отдельно от обязательных min/max. JSON: `score_breakdown.preferred_amount` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегия amount_range; операция: вклад | `bin/router route --strategy amount_range --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-19"></a>19. Конверсия | conversion_24h в оценке; калибровка истории только по настройке. JSON: `score_breakdown.conversion` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегия conversion; Провайдеры | `bin/router route --strategy conversion --seed 42` | [configuration_test.rb](../test/duo_route/configuration_test.rb) |
| <a id="proof-20"></a>20. Загрузка | LoadSafe оценивает свободную ёмкость до достижения запрета. JSON: `score_breakdown.load_safe` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Новый запуск: вес load_safe; операция | `bin/router route --strategy balanced --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-21"></a>21. Бизнес-параметры | Доли, RPM и минимальный/максимальный оборот; явные параметры. JSON: `score_breakdown; turnover_commitments` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Стратегии intensity и turnover_commitment | `bin/router route --strategy turnover_commitment --seed 42` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-22"></a>22. Расширение правил | Реестры Constraints/Policies и загрузка произвольных payment_system. JSON: `eligible_pool; manifest.resolved_configuration` | [policies/registry.rb](../lib/duo_route/policies/registry.rb) | Загрузка других providers в Новый запуск | `bin/router generate --scenario normal --providers 6 --output tmp/generated` | [randomized_backend_test.rb](../test/duo_route/randomized_backend_test.rb) |
| <a id="proof-23"></a>23. Конфликт целей | Сумма весов; при равенстве порядок политик, priority, имя. JSON: `conflicts; tie_break_rule; ranking` | [scorer.rb](../lib/duo_route/scorer.rb) | Операция: конфликт и tie-break | `bin/router explain --operation op_105` | [policies_test.rb](../test/duo_route/policies_test.rb) |
| <a id="proof-24"></a>24. Недостижимые цели | Hard имеет приоритет; предупреждения о недостижимых целях. JSON: `goal_feasibility; target_exceptions` | [reporting/report_builder.rb](../lib/duo_route/reporting/report_builder.rb) | Обзор: исключения целей | `bin/router demo --seed 42` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-25"></a>25. Причины отклонений | Причины исключений и ограничений связываются с отклонениями. JSON: `skip_reasons; target_exceptions; recommendation_details` | [reporting/recommendation_engine.rb](../lib/duo_route/reporting/recommendation_engine.rb) | Обзор; Провайдеры; операция | `bin/router demo --seed 42` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-26"></a>26. Файл решений | final реализован, но настоящая очередь и конкурсный файл ещё отсутствуют. JSON: `routing_decisions_test.json: operation_id, selected_provider, attempts, simulated_result` | [cli/app.rb](../lib/duo_route/cli/app.rb) | Скачивание Decisions показывает публичный формат; финал через CLI | `bin/router final --dry-run` | [final_safety_test.rb](../test/duo_route/final_safety_test.rb) |
| <a id="proof-27"></a>27. Файл отчёта | final формирует сводку и рекомендации; файл ожидает настоящую очередь. JSON: `routing_report_test.json: period, total_operations, distribution, skip_reasons, projected_daily_utilization, recommendations` | [reporting/output_validator.rb](../lib/duo_route/reporting/output_validator.rb) | Скачивание Report публичного запуска; финал через CLI | `bin/router final --dry-run` | [final_safety_test.rb](../test/duo_route/final_safety_test.rb) |
| <a id="proof-28"></a>28. Дополнительные идеи | Генератор, повторение по Manifest, сравнение и два режима timeout. JSON: `manifest; status_check_result; дополнительная идея оценивается жюри` | [generators/scenario.rb](../lib/duo_route/generators/scenario.rb) | Генератор; Стратегии; операция | `bin/router generate --scenario timeouts --output tmp/generated` | [report_generator_test.rb](../test/duo_route/report_generator_test.rb) |
| <a id="proof-29"></a>29. Выступление | Маршрут демонстрации на 4–5 минут в WEB.md; качество выступления заранее не подтверждается. JSON: `Отдельного поля и автоматического доказательства выступления нет` | [cli/app.rb](../lib/duo_route/cli/app.rb) | Показ по WEB.md: Обзор → операция → Стратегии | `bin/router demo --seed 42` | [integration/about_test.rb](../test/integration/about_test.rb) |
| <a id="proof-30"></a>30. Полнота | Маршрутизация, объяснение и отчёт реализованы; финальная очередь ещё ожидается. JSON: `decisions/report; полноту и итоговые баллы определяет жюри` | [runner.rb](../lib/duo_route/runner.rb) | Новый запуск → результат → операция → скачивание | `bin/ci` | [backend_audit_test.rb](../test/duo_route/backend_audit_test.rb) |

<a id="criteria"></a>
## Требования и шкала оценки

Шкала оценки: экспертная оценка — **100**, техническая оценка жюри — **140**, отраслевая — **20**; итог защиты — **160**. Экспертные 100 не прибавляются к 160: они определяют допуск к защите.

Команды приводятся из корня подготовленного проекта. Перед `explain` выполните публичный `demo`. В колонке JSON пути с `manifest.` относятся к отдельному Manifest; остальные — к решению или отчёту. Если свойство проверяется чтением кода или выступлением, отдельного поля результата нет. Наличие теста не означает, что жюри уже начислило баллы.

<a id="experts"></a>
## Экспертная оценка — 100 баллов

### 1. Корректность решения задачи — 22 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| при выборе провайдера учитываются ограничения Hard-constraints и Soft-goals | 12 | 10 обязательных проверок, затем оценка по активным мягким целям; ни один вес не отменяет отказ | [Код, Web, CLI, тест и JSON — 1](#proof-1) |
| при отказе предусмотрен переход к следующему доступному провайдеру и fallback. | 10 | Резерв → ответ → фиксация/откат → следующий; spacepayments после внешних | [Код, Web, CLI, тест и JSON — 2](#proof-2) |

### 2. Гибкость маршрутизации — 33 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| используется несколько способов и факторов распределения платежей между провайдерами | 18 | Семь стратегий и нормированные оценки допустимого пула | [Код, Web, CLI, тест и JSON — 3](#proof-3) |
| разные факторы маршрутизации могут учитываться совместно при выборе провайдера | 8 | Взвешенная сумма оценок активных факторов | [Код, Web, CLI, тест и JSON — 4](#proof-4) |
| решение не привязано к конкретному набору входных данных и допускает изменение параметров провайдеров и правил. | 7 | YAML/JSON, provider_overrides и path=value без изменения формул | [Код, Web, CLI, тест и JSON — 5](#proof-5) |

### 3. Объяснимость маршрутизации — 15 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| понятно, почему для операции выбран конкретный провайдер | 6 | Итоговый рейтинг, причина и вклад целей | [Код, Web, CLI, тест и JSON — 6](#proof-6) |
| понятно, почему другие рассматриваемые провайдеры были исключены | 5 | Полная матрица, реальные значения и границы каждого отказа | [Код, Web, CLI, тест и JSON — 7](#proof-7) |
| можно проследить последовательность действий при отказе и переходе к следующему провайдеру. | 4 | Резерв → ответ → фиксация/откат → следующий; spacepayments после внешних | [Код, Web, CLI, тест и JSON — 2](#proof-2) |

### 4. Качество технической реализации — 20 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| код структурирован, основные части решения разделены по назначению | 8 | Независимый Runner; CLI и Rails — адаптеры; реестры правил | [Код, Web, CLI, тест и JSON — 8](#proof-8) |
| код читаем, названия сущностей и основная логика понятны при просмотре | 7 | Имена компонентов отражают назначение; руководства с командами | [Код, Web, CLI, тест и JSON — 9](#proof-9) |
| предусмотрена обработка основных ошибок и граничных ситуаций. | 5 | Ошибки с путём/кодом; строгая проверка до записи, откат файлов | [Код, Web, CLI, тест и JSON — 10](#proof-10) |

### 5. Аналитика и выводы — 10 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| команда показывает основные показатели распределения платежей между провайдерами | 4 | Факт, цель и отклонение количества/суммы по итоговому маршруту | [Код, Web, CLI, тест и JSON — 11](#proof-11) |
| команда анализирует успешность, отказы, загрузку или использование лимитов | 3 | Успех, отказы, время попыток, ёмкость и история | [Код, Web, CLI, тест и JSON — 12](#proof-12) |
| по результатам сформулированы конкретные выводы или предложения по улучшению маршрутизации. | 3 | Правила с числовым основанием и конкретным изменяемым параметром | [Код, Web, CLI, тест и JSON — 13](#proof-13) |

<a id="technical"></a>
## Техническая оценка — 140 баллов

### 1. Корректность базовой реализации — 22 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| при определении доступных провайдеров соблюдаются Hard-constraints | 7 | 10 обязательных проверок, затем оценка по активным мягким целям; ни один вес не отменяет отказ | [Код, Web, CLI, тест и JSON — 1](#proof-1) |
| при выборе провайдеров соблюдаются Soft-goals | 7 | Семь стратегий и нормированные оценки допустимого пула | [Код, Web, CLI, тест и JSON — 3](#proof-3) |
| после обработки операций корректно обновляется состояние провайдеров | 5 | Принадлежащие Engine резервы, точные суммы, UTC-дни, окно RPM | [Код, Web, CLI, тест и JSON — 14](#proof-14) |
| при отказе выполняется следующая попытка, а при отсутствии доступных внешних провайдеров используется fallback. | 3 | Резерв → ответ → фиксация/откат → следующий; spacepayments после внешних | [Код, Web, CLI, тест и JSON — 2](#proof-2) |

### 2. Гибкость правил маршрутизации — 32 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| распределение по количеству операций | 3 | Projected доля числа операций против traffic_percentage | [Код, Web, CLI, тест и JSON — 15](#proof-15) |
| распределение по объему платежей | 3 | Projected доля суммы против volume_share_pct | [Код, Web, CLI, тест и JSON — 16](#proof-16) |
| распределение по приоритету провайдера | 3 | Нормированный priority задаёт предпочтение в допустимом пуле | [Код, Web, CLI, тест и JSON — 17](#proof-17) |
| распределение по диапазонам суммы: диапазон влияет на выбор между доступными провайдерами, а не только используется как обязательное ограничение | 3 | Предпочтительный диапазон отдельно от обязательных min/max | [Код, Web, CLI, тест и JSON — 18](#proof-18) |
| маршрутизация с учетом успешности / конверсии провайдера | 3 | conversion_24h в оценке; калибровка истории только по настройке | [Код, Web, CLI, тест и JSON — 19](#proof-19) |
| распределение с учетом текущей загрузки: загрузка влияет на выбор между доступными провайдерами, а не только проверяется достижение лимита | 3 | LoadSafe оценивает свободную ёмкость до достижения запрета | [Код, Web, CLI, тест и JSON — 20](#proof-20) |
| маршрутизация с учетом заданной доли трафика и других бизнес-параметров | 3 | Доли, RPM и минимальный/максимальный оборот; явные параметры | [Код, Web, CLI, тест и JSON — 21](#proof-21) |
| параметры правил можно изменять через настройки или конфигурацию без изменения основной логики | 6 | YAML/JSON, provider_overrides и path=value без изменения формул | [Код, Web, CLI, тест и JSON — 5](#proof-5) |
| можно добавлять новые правила и провайдеров без переработки базовой архитектуры. | 5 | Реестры Constraints/Policies и загрузка произвольных payment_system | [Код, Web, CLI, тест и JSON — 22](#proof-22) |

### 3. Согласование целевых правил маршрутизации — 15 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| задан способ совместного учета нескольких целевых факторов при выборе среди доступных провайдеров: приоритеты, веса, скоринг или другой формализованный механизм | 7 | Взвешенная сумма оценок активных факторов | [Код, Web, CLI, тест и JSON — 4](#proof-4) |
| определено правило выбора провайдера для случая, когда разные целевые факторы указывают на разных провайдеров | 4 | Сумма весов; при равенстве порядок политик, priority, имя | [Код, Web, CLI, тест и JSON — 23](#proof-23) |
| определено поведение системы, если текущую цель выполнить невозможно: например, требуемая доля трафика относится к недоступному в данный момент провайдеру. | 4 | Hard имеет приоритет; предупреждения о недостижимых целях | [Код, Web, CLI, тест и JSON — 24](#proof-24) |

### 4. Объяснимость маршрутизации — 10 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| для выбранного провайдера указана конкретная причина выбора | 4 | Итоговый рейтинг, причина и вклад целей | [Код, Web, CLI, тест и JSON — 6](#proof-6) |
| для рассмотренных, но исключенных провайдеров указаны конкретные причины исключения | 4 | Полная матрица, реальные значения и границы каждого отказа | [Код, Web, CLI, тест и JSON — 7](#proof-7) |
| сохранена последовательность рассмотрения провайдеров и повторных попыток. | 2 | Резерв → ответ → фиксация/откат → следующий; spacepayments после внешних | [Код, Web, CLI, тест и JSON — 2](#proof-2) |

### 5. Аналитика качества маршрутизации — 11 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| в отчёте показана фактическая доля операций по каждому провайдеру и её отклонение от заданной доли трафика | 4 | Факт, цель и отклонение количества/суммы по итоговому маршруту | [Код, Web, CLI, тест и JSON — 11](#proof-11) |
| проанализированы успешность, отказы, загрузка и использование лимитов по провайдерам | 3 | Успех, отказы, время попыток, ёмкость и история | [Код, Web, CLI, тест и JSON — 12](#proof-12) |
| определены причины существенных отклонений от целевого распределения или снижения эффективности | 2 | Причины исключений и ограничений связываются с отклонениями | [Код, Web, CLI, тест и JSON — 25](#proof-25) |
| рекомендации содержат конкретное правило или параметр, который предлагается изменить на основании проведенного анализа. | 2 | Правила с числовым основанием и конкретным изменяемым параметром | [Код, Web, CLI, тест и JSON — 13](#proof-13) |

### 6. Качество технической реализации — 10 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| архитектура разделяет основные компоненты решения и позволяет вносить изменения без переработки несвязанных частей | 4 | Независимый Runner; CLI и Rails — адаптеры; реестры правил | [Код, Web, CLI, тест и JSON — 8](#proof-8) |
| код и структура проекта позволяют понять логику решения и порядок его запуска | 3 | Имена компонентов отражают назначение; руководства с командами | [Код, Web, CLI, тест и JSON — 9](#proof-9) |
| предусмотрена обработка технических ошибок, некорректных входных данных и граничных ситуаций. | 3 | Ошибки с путём/кодом; строгая проверка до записи, откат файлов | [Код, Web, CLI, тест и JSON — 10](#proof-10) |

### 7. Наличие требуемых файлов — 40 баллов

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| в корне главного репозитория с кодом в ветке main лежит файл routing_decisions_test.json со всеми заявками из operations_queue_test.json в правильной структуре | 20 | final реализован, но настоящая очередь и конкурсный файл ещё отсутствуют | [Код, Web, CLI, тест и JSON — 26](#proof-26) |
| в корне главного репозитория с кодом в ветке main лежит файл routing_report_test.json, включающий аналитику роутингов из routing_decisions_test.json и рекомендации  в правильной структуре. | 20 | final формирует сводку и рекомендации; файл ожидает настоящую очередь | [Код, Web, CLI, тест и JSON — 27](#proof-27) |

<a id="industry"></a>
## Отраслевая оценка — 20 баллов

### 1. Реализация дополнительных идей

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| Свободный выбор | 6 | Генератор, повторение по Manifest, сравнение и два режима timeout | [Код, Web, CLI, тест и JSON — 28](#proof-28) |

### 2. Выступление команды (умение презентовать результаты своей работы, строить логичный, понятный и интересный рассказ для презентации результатов своей работы)

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| Хорошее выступление и презентация | 6 | Маршрут демонстрации на 4–5 минут в WEB.md; качество выступления заранее не подтверждается | [Код, Web, CLI, тест и JSON — 29](#proof-29) |

### 3. Полнота проработки решения

| Точный пункт ТЗ | Баллы | Как выполнено | Проверка |
|---|---:|---|---|
| Решение выполнено полностью покрывает поставленную задачу | 8 | Маршрутизация, объяснение и отчёт реализованы; финальная очередь ещё ожидается | [Код, Web, CLI, тест и JSON — 30](#proof-30) |

<a id="files"></a>
## Обязательные файлы для автоматической проверки

По ТЗ файлы должны лежать **в корне главного репозитория в ветке main** с точными именами; отсутствие, неверное имя, место или структура означает, что файл не приложен.

| Файл | Баллы | Обязательный контракт | Текущий статус |
|---|---:|---|---|
| `routing_decisions_test.json` | 20 | Все ID из настоящей очереди; operation_id, selected_provider, attempts с provider/decision/reason, simulated_result. Enum decision: selected/skipped; result: approved/rejected/expired. DuoRoute также требует latency_sec из примера ТЗ | Ожидается настоящая очередь |
| `routing_report_test.json` | 20 | period, total_operations, distribution, skip_reasons, projected_daily_utilization, recommendations; согласованность с decisions | Ожидается настоящая очередь |

Защищённая команда и проверка покрытия — [финальный запуск](CLI.md#final). Окончательный валидатор ещё не получен; публичный валидатор проверяет только 10 известных ID.

<a id="constraints"></a>
## Обязательные ограничения

10 классов дают 11 кодов отказа: банковская проверка имеет два кода. Ниже условие **допуска**. Для числового лимита null означает отсутствие ограничения. Все проверки выполняются до оценки и сохраняются, даже если первая уже не пройдена.

Все классы — `DuoRoute::Constraints` в [registry.rb](../lib/duo_route/constraints/registry.rb). Для каждой строки Web: **страница операции → матрица ограничений**, CLI: `bin/router explain --operation op_103` после demo, либо `explain --decisions PATH --operation ID` для своей операции. В JSON: `constraint_matrix` и `attempts.reason`. Тест границ каждой проверки — [ConstraintsTest](../test/duo_route/constraints_test.rb) и [BackendAuditTest](../test/duo_route/backend_audit_test.rb).

| Поле | Условие допуска | Reason code отказа | Класс | Тест границы |
|---|---|---|---|---|
| status | равно active | provider_inactive | Status | active / inactive |
| limit_amount_min | amount ≥ min | amount_below_minimum | AmountMinimum | ниже / равно / выше |
| limit_amount_max | amount ≤ max | amount_exceeds_limit | AmountMaximum | ниже / равно / выше |
| daily_approved_amount, daily_amount_limit | daily + amount ≤ limit | daily_amount_limit_exceeded | DailyAmount | равенство, превышение, decimal |
| in_progress_count, in_progress_count_limit | count + 1 ≤ limit | in_progress_count_limit_exceeded | InProgressCount | ниже / равно / выше |
| in_progress_amount, in_progress_amount_limit | amount_in_progress + amount ≤ limit | in_progress_amount_limit_exceeded | InProgressAmount | ниже / равно / выше |
| banks, exclude_banks | пустой список либо банк включён при include / отсутствует при exclude | bank_not_in_list / bank_excluded | Bank | пустой / include / exclude |
| provider_margin_pct, merchant_margin_pct, allow_negative_agreement | provider ≤ merchant либо agreement строго true | negative_margin_not_allowed | Margin | ниже / равно / выше; boolean |
| available_requisites | целое > 0 | no_available_requisites | Requisites | 0 / 1 / 2; неверные типы |
| requests_per_minute_limit | реальные вызовы в (t−60,t] + 1 ≤ limit | rate_limit_exceeded | RateLimit | 59.999 / 60 / 60.001 секунды; граница лимита |

<a id="strategies"></a>
## Семь стратегий и совместная работа

Классы `DuoRoute::Policies` находятся в [registry.rb](../lib/duo_route/policies/registry.rb); каждая строка проверена [PoliciesTest](../test/duo_route/policies_test.rb), расширенные границы — [BackendAuditTest](../test/duo_route/backend_audit_test.rb). Стандартная конфигурация — [strategies.yml](../config/routing/strategies.yml); изменения — `provider_overrides.NAME.FIELD`, веса — `presets.STRATEGY.weights.POLICY`. Web для каждой: одноимённая карточка на **Стратегиях**, затем **Новый запуск** и вклад цели на **странице операции**.

| Стратегия / класс | Поля | Формула или порядок | CLI | Фактор JSON |
|---|---|---|---|---|
| count_share / CountShare | traffic_percentage | 1 − абсолютное отклонение projected доли / 100 | `bin/router route --strategy count_share` | score_breakdown.count_share |
| volume_share / VolumeShare | volume_share_pct | Та же формула по сумме | `bin/router route --strategy volume_share` | score_breakdown.volume_share |
| cascade / Cascade | priority | Меньше priority — раньше; нормализация по допустимому пулу | `bin/router route --strategy cascade` | score_breakdown.cascade |
| amount_range / PreferredAmount | preferred_amount_min/max | 1 внутри, линейное уменьшение вне диапазона | `bin/router route --strategy amount_range` | score_breakdown.preferred_amount |
| conversion / Conversion | conversion_24h | Значение 0–1; калибровка только явно | `bin/router route --strategy conversion` | score_breakdown.conversion |
| intensity / Intensity | requests_per_minute_limit, RPM | 1 − (RPM+1)/limit | `bin/router route --strategy intensity` | score_breakdown.intensity |
| turnover_commitment / TurnoverCommitment | daily_turnover_min/max, daily | Повышение при недоборе min, 0.65 внутри, 0 при превышении max | `bin/router route --strategy turnover_commitment` | score_breakdown.turnover_commitment |

Полные формулы — [алгоритм](ALGORITHM.md#scoring). Дополнительные факторы load_safe, latency и economy участвуют в balanced/custom. Итоговая оценка `Σ(w×s)/Σw` учитывает только активные и определённые для кандидата факторы. Разногласие целей записывается как `policy_winners_disagree`; равенство разрешается порядком политик, priority провайдера и именем. Нулевой вес не участвует ни в оценке, ни в равенстве. Недоступность провайдера важнее любой цели; report объясняет недостижимые доли.

Проверка комбинации: `bin/router route --strategy balanced --seed 42`; изменение веса — `--set presets.balanced.weights.conversion=5`. Web: флажок изменения весов в новом запуске. Код: [Scorer](../lib/duo_route/scorer.rb), тесты: [PoliciesTest](../test/duo_route/policies_test.rb), [RandomizedBackendTest](../test/duo_route/randomized_backend_test.rb).

<a id="cascade"></a>
## Каскад и резервный маршрут

1. Engine проверяет обязательные ограничения и ранжирует внешних кандидатов.
2. `reserve` занимает число/сумму in-progress и добавляет реальный вызов в RPM.
3. Симулятор возвращает ответ и время.
4. При `approved` — `commit`: освобождение резерва, рост одобренного daily, завершение операции.
5. При `rejected` — `rollback`: освобождение резерва; RPM остаётся. Следующий кандидат не должен нарушать ограничения.
6. При `expired` стандартный `fallback_on_timeout` делает rollback и переход. `hold_until_status` удерживает резерв до синхронной проверки: late approved фиксирует, late rejected освобождает и продолжает, неизвестный статус сохраняет резерв и expired.
7. Внешний провайдер не вызывается дважды. При исчерпании внешних кандидатов проверяется и вызывается spacepayments.
8. Недоступный fallback останавливает весь расчёт до публикации результата. Его rejected/expired сохраняется честно как итоговый ответ, не превращается в approved.

Код: [Engine](../lib/duo_route/engine.rb), [State::Store](../lib/duo_route/state/store.rb), [симуляторы](../lib/duo_route/simulation). CLI: `bin/router demo --seed 42`, затем `bin/router explain --operation op_101`. Web: операция op_101 публичного запуска. Тесты: [EngineTest](../test/duo_route/engine_test.rb), [BackendAuditTest](../test/duo_route/backend_audit_test.rb): 27 сочетаний результатов × 2 режима timeout × 3 поздних статуса = 162 ветви.

<a id="edges"></a>
## Пограничные ситуации

Ошибки InputError дают path/code/message и exit 2 без нового результата. В таблице сокращения классов: BackendAuditTest — [backend_audit_test.rb](../test/duo_route/backend_audit_test.rb), InputValidationTest — [input_validation_test.rb](../test/duo_route/input_validation_test.rb), ConfigurationTest — [configuration_test.rb](../test/duo_route/configuration_test.rb), FinalSafetyTest — [final_safety_test.rb](../test/duo_route/final_safety_test.rb), RoutingFlowTest — [routing_flow_test.rb](../test/integration/routing_flow_test.rb). Остальные тесты находятся в [test/duo_route](../test/duo_route).

| Ситуация | Поведение | Тест |
|---|---|---|
| Пустые/пробельные JSON, YAML, CSV | empty_file | BackendAuditTest: JSON YAML CSV… |
| Повреждённые JSON/YAML/CSV | malformed_json/malformed_yaml/malformed_csv | BackendAuditTest, InputValidationTest |
| Неверный корень JSON/config/history | path + wrong_type/invalid_configuration | BackendAuditTest, ConfigurationTest |
| Нет обязательного поля, null | required и точный путь; numeric/string проверяются отдельно | BackendAuditTest mandatory fields, InputValidationTest |
| Пустые строки/пробелы в ID, банке, статусе | wrong_type | BackendAuditTest mandatory fields |
| Неизвестные дополнительные payload поля | Сохраняются во входе, не участвуют в выборе | BackendAuditTest JSON… |
| Неизвестные настройки/overrides | invalid_configuration, известные catalogue defaults для другого набора не применяются | ConfigurationTest, BackendAuditTest provider… |
| Файл >128 MiB | file_too_large до парсинга; чтение ограничено MAX_BYTES+1 | BackendAuditTest JSON… |
| Upload/text >10 MiB | Ошибка до создания run; Rack может вернуть 400 раньше контроллера | RoutingFlowTest oversized textarea |
| Не-UTF-8 | invalid_encoding | BackendAuditTest JSON… |
| Дубли CSV-заголовков, пустые имена | invalid_csv_headers | BackendAuditTest JSON… |
| Лишняя/недостающая CSV-колонка | csv_column_count с номером строки | BackendAuditTest JSON… |
| Header-only история | [] и явный snapshot fallback; final history отклоняет пустую историю | BackendAuditTest, FinalSafetyTest |
| Пустая очередь | empty_queue | InputValidationTest |
| Одна операция | Полный результат | EngineTest, BackendAuditTest |
| Большая очередь | Полная обработка и проверка coverage | script/benchmark_backend.rb: 10k и 50k |
| Повтор ID / отсутствующий ID | duplicate_operation_id / required | InputValidationTest, BackendAuditTest |
| Сумма 0 / отрицательная / строка / null / NaN / Infinity | Ошибка поля amount | BackendAuditTest mandatory fields |
| Дробные суммы и тысячи накоплений | BigDecimal; 1000 × 0.1 = 100 | BackendAuditTest decimal… |
| Очень большие целые | Поддерживаются, тест 10^40 | BackendAuditTest decimal… |
| Число JSON теряет decimal precision при преобразовании в Float | unsupported_precision с путём; не исправляется молча | Loader#json_numbers; Money#number |
| Дневная граница 0.1+0.2=0.3 и превышение 0.000001 | Ровно лимит допустимо; превышение отклоняется | BackendAuditTest decimal… |
| Неверная дата, 30 февраля, час 25, timezone отсутствует | invalid_iso8601 | BackendAuditTest mandatory fields |
| Одинаковое время / переставленные операции | Stable sort по абсолютному времени и исходному индексу | EngineTest order, RandomizedBackendTest |
| Разные timezone / раньше snapshot | Нормализация в UTC / before_snapshot | BackendAuditTest UTC days |
| Полночь / пропуск дней / несколько суток | daily сбрасывается, in-progress и RPM сохраняют смысл | BackendAuditTest UTC days, benchmark 50k |
| Пустой банк / неизвестный банк | Пустой — ошибка; неизвестный допустим только по bank filter | BackendAuditTest, ConstraintsTest |
| Пустой список providers | empty_providers | BackendAuditTest provider… |
| Duplicate payment_system / несколько spacepayments | duplicate_payment_system | InputValidationTest, BackendAuditTest |
| Нет fallback / неактивен / нет реквизитов | fallback_missing/fallback_unavailable | BackendAuditTest, EngineTest |
| Только fallback | Допустим, весь трафик через self-provider | BackendAuditTest provider… |
| Неизвестный fallback в config | invalid_configuration | BackendAuditTest provider… |
| Лимиты 0 / ниже 0 / min>max | Нулевой запрещает новую положительную нагрузку; отрицательные/диапазон — ошибка | boundary table, provider edge tests |
| Счётчики snapshot уже выше лимита | Сохраняются; провайдер исключается, report предупреждает | BackendAuditTest provider… |
| Доля <0/>100 / count сумма !=100 | Ошибка диапазона/traffic_share_sum | InputValidationTest, BackendAuditTest |
| Volume сумма !=100 / optional-поле отсутствует | Без молчаливой нормализации; target_exceptions предупреждает; nil policy пропускается | RunSelectionTest, PoliciesTest |
| Banks пуст / include / exclude | Unrestricted / allowlist / denylist | ConstraintsTest, randomized |
| Маржа ниже/равно/выше, agreement неверного типа | Включительная граница; исключение только boolean true | BackendAuditTest table/mandatory fields |
| Available requisites 0/1/2, дробь/negative/null | 0 исключает; целые ≥1 проходят; неверный ввод отклоняется | BackendAuditTest table/mandatory fields |
| RPM ниже/равно/выше, событие 59.999/60/60.001 назад | Окно (t−60,t]; реальный отказ не убирает RPM | BackendAuditTest RPM… |
| Первый approved / rejected→approved / все rejected | Остановка / следующий / fallback | EngineTest, полный перебор BackendAuditTest |
| Expired в двух режимах; поздний approved/rejected/unknown | Rollback+next или hold; commit/rollback/сохранение pending | Все 162 сочетания BackendAuditTest |
| Fallback approved/rejected/expired/недоступен | Честный итоговый enum; недоступный fallback прерывает весь run | BackendAuditTest cascade, EngineTest |
| Повторный commit/rollback | Commit требует активный reserve; rollback без него идемпотентен и не трогает snapshot | Store, StateTest |
| Пустая/отсутствующая/малая история | Явный source=provider_snapshot; final требует непустой файл при history | ConfigurationTest, BackendAuditTest, FinalSafetyTest |
| n<minimum/n=minimum / только один status | Snapshot ниже порога; профиль по частотам на пороге | ConfigurationTest, BackendAuditTest history… |
| Unknown status/provider, отрицательная latency, дубли строк | Ошибки с полем/строкой | BackendAuditTest history errors |
| История после snapshot или операция ещё не завершена к snapshot | Исключается до профилей и calibration; число исключённых строк в manifest | BackendAuditTest future history |
| Custom probabilities !=100% | invalid_configuration | ConfigurationTest |
| Одинаковые/разные seed | Воспроизводимость / разные потоки возможны | SimulationTest, RandomizedBackendTest |
| Неактивная целевая доля, исчерпанные лимиты, неподдерживаемый банк | Hard имеет приоритет; причины и рекомендации в report | generated scenarios, randomized, ConstraintsTest |
| Count/volume/conversion/turnover конфликтуют | Явные веса и policy_winners_disagree | PoliciesTest, evaluate-default |
| Все soft policies выключены / сумма весов 0 | Конфигурация отклоняется с zero_weights; нет скрытого режима | InputValidationTest, BackendAuditTest zero weight |
| Равный score | Стабильный порядок; нулевой вес не участвует | PoliciesTest, BackendAuditTest zero weight |
| Повторный запуск CLI/Web/Job | Decisions стабильны; completed job не выполняется второй раз | FinalSafetyTest, RunSelectionTest, RoutingFlowTest |
| Изменение входных объектов | Входы глубоко копируются, не меняются | BackendAuditTest inputs… |
| Ошибка parse/расчёта/validator/второго rename | Старые результаты остаются/восстанавливаются, temp убираются | CliTest, FinalSafetyTest |
| Symlink/hardlink на вход | Перезапись отвергается | FinalSafetyTest |
| Неверные output enum/latency/reason/attempt/coverage/amount | Строгая проверка в Runner для обоих adapters, затем CLI проверяет staged JSON | BackendAuditTest output…, OutputValidator |


Денежные счётчики используют BigDecimal, включая дроби мельче копейки. JSON остаётся числовым; непредставимая без потерь дробь вызывает явную ошибку. Очень большие значения в браузере ограничены JavaScript Number. Это не меняет обязательные проверки ядра.

<a id="default"></a>
## Независимый выбор default

Default — `balanced`, версия `paired-final-v1-2026-09-06`. Balanced — единственный проверенный статический кандидат с worst-case regret успешности не выше 0,1 п.п. и на validation, и на holdout. Кандидат `amount_range` имеет больший worst-case regret на holdout. Глобальная оптимальность не доказана. Краткие метрики и веса — в [записи default](../config/routing/default_selection.json).

Исследование использует раздельные development, validation и holdout seeds, одинаковые входы и ответы для кандидатов и независимый аудит обязательных ограничений. Regret — разница с лучшим допустимым кандидатом в том же сценарии, в единицах соответствующей метрики. Сначала сравнивается worst-case regret неуспешности, затем средняя неуспешность, fallback и цели распределения. Holdout проверяет зафиксированного кандидата; рабочие веса автоматически не меняются.

Это ограниченное исследование синтетических сценариев, а не прогноз финального трафика. Симуляция использует среднюю latency провайдера. Статистическая значимость и перенос на неизвестное распределение не доказаны. Нет обещания точного достижения недостижимых долей.

Воспроизведение (длительное исследование, вне CI):

```bash
ruby script/evaluate_default_final.rb tmp/repeated-study.json
ruby script/replay_default_final.rb tmp/repeated-study.json
ruby script/summarize_default_final.rb tmp/repeated-study.json
```

`bin/router evaluate-default` — отдельная диагностика с результатом в `tmp/default_strategy_evaluation.json`, не источник конфигурации по умолчанию.

<a id="verification"></a>
## Автоматические проверки и производительность

Запускайте проверки из корня репозитория:

```bash
ruby script/check_production_docs.rb
ruby script/check_markdown_links.rb
bin/rails test
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
bin/rails zeitwerk:check
bin/router readiness
```

Проверка документации проверяет пользовательские тексты, примеры конфигурации и локальные ссылки; она включена в CI и readiness. Ошибки содержат файл, строку и причину, код завершения — 1.

[Тесты независимого аудита](../test/duo_route/submission_audit_test.rb) проверяют повреждение результатов, состояние, итоговый маршрут, семантику попыток и отчёт. [Схемы](../test/duo_route/schema_test.rb) проверяются на реальных данных. [Web-тесты](../test/integration/routing_flow_test.rb) проверяют загрузку и ошибки входов. [Проверки сравнения](../test/duo_route/comparison_semantics_test.rb) фиксируют одинаковые цели, отсутствующие значения и итогового провайдера.

Независимый аудитор воспроизводит состояние по фактическим `attempts`, проверяет десять ограничений, fallback, распределение, производительность провайдеров и дневную историю. `--config` закрепляет конфигурацию. Аудит не доказывает реальные внешние ответы, исходный RPM и оптимальность. Неполные попытки без результата и времени ответа отклоняются.

Строгая репетиция `bin/router rehearse-final` возвращает ненулевой код при reference mismatch: статический эталон может требовать первоначального кандидата после его отказа. `--allow-reference-mismatch` разрешает только проверенное расхождение этого типа; семантический аудит остаётся обязательным. Подробности — [CLI](CLI.md#readiness).

Производительность зависит от среды и входов; предел 700 МБ для всего final pipeline не подтверждён. Локальные замеры можно повторить:

```bash
ruby script/profile_audit.rb 1000 full
ruby script/profile_audit.rb 1000 submission
ruby script/benchmark_backend.rb 10000 20 100000
```

Профили full и submission показывают удерживаемую память объяснения; она не равна peak RSS. Web сохраняет full. CLI final использует submission, сохраняя данные для независимого аудита.

<a id="security"></a>
## Безопасность и локальные данные

- JSON/CSV разбираются стандартными парсерами, YAML — `safe_load` без aliases, классов и symbols. Вход не исполняется; неизвестная конфигурация отклоняется.
- CLI читает максимум 128 MiB, Web — 10 MiB на upload или текстовое поле. UTF-8, колонки CSV и типы проверяются. Rack может раньше отклонить большую форму с HTTP 400.
- URL не задаёт путь к файлу: документы и восемь типов скачиваний выбираются из закрытых списков. CLI запрещает совпадение выходов со входами, включая symlink/hardlink.
- Rails фильтрует реквизиты, телефоны и полные входные поля в логах; UI маскирует телефон, задание очищает похожие фрагменты ошибок. Исходные скачиваемые файлы и audit могут содержать чувствительные данные.
- Маршрутизация не использует сеть; CDN и телеметрии нет. Chart.js 4.4.7 поставляется локально по MIT. [Сторонние компоненты](../THIRD_PARTY_NOTICES.md) перечислены отдельно.
- Внешние API и секреты провайдеров не добавлены. Локальный Rails master.key исключён из Git; зашифрованный credentials из шаблона не является открытым секретом.
- SQLite хранит локальные входы и результаты. Внешней репликации и пользовательской авторизации нет; сервер разработки слушает 127.0.0.1. Удаление истории выполняет оператор в локальной базе.
- Временные результаты CLI имеют права 0600, проверяются перед заменой, защищены flock; при обычном исключении прежний набор восстанавливается. CSP можно включить штатным Rails initializer; это не заявление о включённой строгой политике.

Код: [Loader](../lib/duo_route/input/loader.rb), [RoutingRunsController](../app/controllers/routing_runs_controller.rb), [AboutController](../app/controllers/about_controller.rb), [фильтры параметров](../config/initializers/filter_parameter_logging.rb), [CLI](../lib/duo_route/cli/app.rb). Проверки: Brakeman, [FinalSafetyTest](../test/duo_route/final_safety_test.rb), [AboutTest](../test/integration/about_test.rb), [RoutingFlowTest](../test/integration/routing_flow_test.rb).

<a id="limitations"></a>
## Честные ограничения

- **Batch-модель:** операции последовательны в логическом created_at. Время ответа не сдвигает следующие операции; одновременные выплаты и произвольные поздние события не моделируются. Исторический RPM не восстанавливается, исходная занятость снимка остаётся внешней нагрузкой.
- **Память:** Web хранит полное объяснение, final использует submission; запись и повторный разбор больших JSON требуют больше памяти, чем один Runner. Замеры не являются SLA.
- **Файлы:** атомарная замена каждого файла и откат при обычной ошибке не гарантируют единую транзакцию двух имён при SIGKILL/отключении питания. Читатель без блокировки может кратко увидеть смешанную пару; после сбоя следует повторить final и проверить оба файла.
- **Провайдеры:** настоящих API нет, результаты симулируются. Выбранный провайдер не означает успешную выплату.
- **Стратегия:** глобальный оптимум и точные доли на неизвестной очереди математически не гарантированы. Default проверен на ограниченных синтетических и публичных сценариях; часть показателей holdout хуже других кандидатов, Pareto по средним не подтверждает его превосходства.
- **История:** учитываются только завершённые строки до snapshot; небольшая выборка даёт явный переход к параметрам снимка. Деньги с неподдерживаемой точностью отклоняются без молчаливого округления.
- **Валидатор:** публичный скрипт трактует traffic_percentage=0 как запрет, а ТЗ — как мягкую цель. Ядро следует ТЗ; публичный набор не содержит внешнего провайдера с такой долей. Таймаут в режиме `fallback_on_timeout` ведёт к следующему, режим `hold_until_status` удерживает резерв до проверки статуса.
- **Web:** development Active Job async живёт в процессе; после аварии queued/running задания автоматически не возобновляются. Completed сохраняются. Нет отмены задания и многопользовательской авторизации.
- **Финал:** настоящая очередь и окончательный валидатор ещё не получены. Конкурсные `_test`-файлы отсутствуют; 40 баллов за файлы пока нельзя считать подтверждёнными.
