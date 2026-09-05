# Входы и выходы

## Входы

`providers.json` — object с `snapshot_at`, `gateway`, `merchant`, `providers[]`. Обязательные provider fields соответствуют публичному файлу. Опциональные `volume_share_pct`, `preferred_amount_min/max`, `requests_per_minute_limit`, `daily_turnover_min/max` задаются напрямую или через `provider_overrides` config.

Operations — JSON array. Обязательны уникальный `operation_id`, ISO-8601 `created_at`, положительный numeric `amount`, непустой `bank`. `payout_requisite` сохраняется как input, но не попадает в logs; UI показывает маску телефона.

History CSV columns: `operation_id,created_at,amount,bank,card_brand,payment_system,status,latency_sec`. Используется для analytics/calibration, не hard eligibility.

Config — YAML/JSON: `routing`, `simulation`, `calibration`, `provider_overrides`, `presets.*.weights` и optional `policy_priorities`. YAML aliases и object tags запрещены.

Scripted outcomes допускает flat key:

```json
{"outcomes":{"op_1:vipay":{"result":"rejected","latency_sec":18}},"default":{"result":"approved","latency_sec":24}}
```

## Decisions

Обязательный совместимый слой: `operation_id`, `selected_provider`, `attempts[]` (`provider`, `decision`, `reason`), `simulated_result`, `latency_sec`. `decision` только `selected|skipped`, result только `approved|rejected|expired`, ровно одна попытка selected.

Расширения: `strategy`, `score`, `score_breakdown`, `eligible_pool`, `ranking`, `constraint_matrix`, `conflicts`, `tie_break_rule`, `state_before/after`, `fallback_used`, `status_check_result`, `decision_time_ms`.

Hard reason codes: `provider_inactive`, `amount_below_minimum`, `amount_exceeds_limit`, `daily_amount_limit_exceeded`, `in_progress_count_limit_exceeded`, `in_progress_amount_limit_exceeded`, `bank_not_in_list`, `bank_excluded`, `negative_margin_not_allowed`, `no_available_requisites`, `rate_limit_exceeded`.

Flow codes: `lower_combined_score`, `provider_rejected`, `provider_expired`, `provider_expired_status_rejected`, `highest_combined_score`, `timeout_held_until_status`, `external_pool_exhausted`.

## Report

Совместимые поля: `period`, `total_operations`, `distribution`, `skip_reasons`, `projected_daily_utilization`, `recommendations` (array strings).

Расширения: total amount, volume distribution/deviation, results, approval/fallback/latency, provider performance, full capacity start/end, turnover commitments, target exceptions, history analytics, structured `recommendation_details`, SHA-256/seed/schema/app/Ruby manifest.

JSON формируется UTF-8 через `JSON.pretty_generate`. Ключи строятся в фиксированном порядке; одинаковые decisions при одинаковых input/config/seed детерминированы.

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

Для старых конфигураций сохранён `simulation.expired_rate`: при отсутствии достаточной истории это абсолютная доля Expired, ограниченная остатком после Approval. Новые конфигурации используют `failure_expired_share`; не задавайте одновременно оба способа, если не нужна совместимость со старым запуском.
