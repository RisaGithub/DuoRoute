# Сценарий защиты на 4–5 минут

## 0:00–0:35 — проблема

Открыть Dashboard. Сказать: «DuoRoute не угадывает одного лучшего провайдера. Он сначала гарантирует hard eligibility, затем прозрачно согласует несколько бизнес-целей в online-потоке».

Показать KPI и count target-vs-fact. Отметить, что payflow начинает почти у daily max, а quickpay принимает больше банков и крупных чеков — точная цель на короткой очереди недостижима, и report объясняет почему.

## 0:35–1:35 — главное решение

Открыть Public demo run → `op_103`. Показать:

1. Заголовок «почему выбран quickpay».
2. Timeline: vipay/payflow исключены по amount max.
3. Hard matrix — проверены все constraints, не только первый failure.
4. Waterfall — вклад projected count/volume, conversion, load, turnover, economy.
5. State before/after — daily вырос только у approved provider.

## 1:35–2:20 — cascade и timeout

В public run открыть операцию с `provider_rejected`/`provider_expired` в timeline. Пояснить reserve → reject rollback → следующий provider. В New run переключить `hold_until_status`; подчеркнуть, что official default остаётся `fallback_on_timeout` из письменного ТЗ, но production-трактовка Q&A покрыта второй веткой.

## 2:20–3:05 — Strategy Lab

Выбрать balanced, cascade, conversion_first, load_safe и запустить сравнение. Показать trade-off: approval/fallback/latency и суммарное отклонение долей. Подчеркнуть reset исходного snapshot и подпись counterfactual.

## 3:05–3:45 — аналитика

Открыть Analytics: empirical conversion/latency из 100 history rows, snapshot остаётся canonical. Показать рекомендации с числовым evidence: utilization, deviation, success samples, turnover deficit.

## 3:45–4:25 — устойчивость

Открыть Data Generator, выбрать `fallback`, `timeouts` или `invalid_data`: preview / run now. Сказать про seeded reproducibility и invariant test на сотнях операций. На терминале:

```bash
bin/router demo --seed 42
ruby script/validate_10.rb routing_decisions.json
```

Ожидаемый итог validator: 29 passed, 0 errors, 0 warnings.

## 4:25–4:50 — stopcode

Показать одну команду `bin/router final ...`. Она отказывается от файла с неправильным basename, сначала валидирует всё, затем пишет два точных имени. Публичные файлы не маскируются под `_test`.
