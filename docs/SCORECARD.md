# Scorecard: критерий → доказательство

| Блок | Реализация | Тест / проверка | Экран / команда |
|---|---|---|---|
| Hard constraints | 10 независимых объектов, полный audit matrix, inclusive bounds, nil semantics | `constraints_test.rb`, randomized invariant | Operation detail / `bin/router explain` |
| State update | reserve/commit/rollback, daily/in-progress, 60-sec RPM | `state_test.rb`, `engine_test.rb` | state before/after |
| Reject + fallback | пересчёт cascade; self-provider только после external exhaustion | engine cascade/fallback tests | attempt timeline |
| Timeout modes | `fallback_on_timeout` + `hold_until_status` со status-check | 3 timeout branch tests | wizard + timeline |
| Гибкость (33) | 9 policies, 7 стратегий и комбинированные настройки, YAML weights/priorities/overrides, registry | policy unit tests | Стратегии + config editor |
| Совместный учёт | формальная weighted normalized sum | combined/conflict tests | waterfall и ranking |
| Count / volume | projected state, не прошлый snapshot | projected policy tests | target-vs-fact chart/report |
| Cascade / amount | priority и отдельный preferred range | policy tests | score breakdown |
| Conversion / load / RPM | canonical conversion, projected capacity, sliding window | policy + constraint tests | provider drill-down |
| Turnover / economy | min/max commitment и margin spread | policy/report tests | Рекомендации на Обзоре |
| Детерминизм | stable operation order/tie-break; SHA seeded simulator | simulator/order/tie tests | manifest download |
| Объяснимость (15) | hard reasons, eligible ranking, contributions, conflicts, timeline | exact output/audit tests | Operation detail |
| Аналитика (10) | count/volume, result mix, fallback, latency, capacity, history, target exceptions | report/history tests | Обзор + Провайдеры |
| Рекомендации | deterministic threshold rules с evidence/action/rationale | report recommendation test | Страница запуска |
| Входные ошибки | aggregate path/line errors, safe YAML, duplicates, malformed data | input validation tests | wizard error state / `validate` |
| Генератор | 8 scenarios, seeded data/outcomes/history | reproducibility/invalid/invariant tests | Data Generator / `generate` |
| Core boundaries | core без Rails; CLI/job — adapters | Zeitwerk + integration tests | architecture docs |
| Web flow | upload/manual → prevalidation → job → polling → detail → download | `routing_flow_test.rb` | все основные страницы |
| Security | 10 MB, no path params, filters/masks, offline assets | Brakeman, integration | wizard/security docs |
| Два файла (40) | guarded `final`, strict output validator, atomic temp+rename | CLI tests | `bin/router final` |
| Public contract | обязательные fields/enums/coverage | internal validator + organizer script | `routing_decisions.json` |

Текущая фактическая test suite: 57 runs, 11 314 assertions; точные актуальные числа следует брать из последнего `bin/rails test`, а не из этой строки при изменении тестов.
