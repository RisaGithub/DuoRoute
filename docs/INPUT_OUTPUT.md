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
