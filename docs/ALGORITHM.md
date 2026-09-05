# Алгоритм маршрутизации

## Online semantics

Очередь сортируется по `created_at`; равные timestamps сохраняют входной индекс. Будущие операции не участвуют в решении. Перед каждой операцией применяется состояние после всех предшествующих попыток и status-check событий.

## Hard constraints

Внешний провайдер eligible, только если одновременно выполнены:

- `status == active`;
- `min <= amount <= max` для заданных границ;
- `daily_approved + amount <= daily_amount_limit`;
- `in_progress_count + 1 <= limit`;
- `in_progress_amount + amount <= limit`;
- пустой `banks` разрешает любой банк; include list требует присутствия; при `exclude_banks=true` перечисленные банки запрещены;
- `provider_margin_pct <= merchant_margin_pct`, кроме `allow_negative_agreement=true`;
- `available_requisites > 0`;
- projected attempts за окно `(created_at - 60 sec, created_at]` не превышают RPM limit.

`nil` у числового лимита означает отсутствие лимита. Все проверки выполняются даже после первого failure для audit matrix; reason попытки берётся из первого стабильного failure по порядку registry.

## Soft scoring

Каждая активная policy возвращает `sᵢ ∈ [0,1]`. Итог:

`combined(p) = Σ(sᵢ(p) × wᵢ) / Σwᵢ`, где учитываются только policies, вернувшие score для данного провайдера.

- Count: `1 - |projected_count_share - traffic_percentage| / 100`.
- Volume: `1 - |projected_volume_share - volume_share_pct| / 100`.
- Cascade: линейная нормализация priority, меньшее значение лучше.
- Preferred amount: 1 внутри preferred range, вне — линейный штраф по относительному расстоянию.
- Conversion: snapshot `conversion_24h` или opt-in `effective_conversion`.
- Load: `1 - max(projected daily, in-progress count, in-progress amount utilization)`.
- Intensity: `1 - projected_rpm / rpm_limit`.
- Turnover: boost при недоборе minimum, neutral внутри коридора, 0 выше soft maximum.
- Economy: `(merchant_margin - provider_margin) / merchant_margin`.

Значения ограничиваются `[0,1]`. Отсутствующее optional field возвращает `nil`, а не ноль.

## Конфликт и tie-break

Если лучшие кандидаты отдельных policies различаются, decision получает `policy_winners_disagree`. Конфликт разрешает weighted combined score. При точном равенстве: normalized scores в порядке `policy_priorities`, затем `provider.priority`, затем лексикографический `payment_system`. Seed не участвует в выборе.

## State lifecycle

Перед фактической попыткой engine атомарно резервирует in-progress count/amount и добавляет timestamp RPM.

- `approved`: reservation освобождается, сумма добавляется в daily approved;
- `rejected/cancelled`: reservation откатывается, RPM остаётся фактом вызова, кандидат исключается;
- `expired + fallback_on_timeout` (official default): reservation откатывается, выполняется следующий кандидат;
- `expired + hold_until_status`: capacity удерживается до scripted/seeded status check; поздний approved коммитит, late rejected откатывает и продолжает cascade. Уже принятые решения не пересчитываются.

Count/volume queue distribution увеличивается только для итогового `selected_provider`, включая fallback, независимо от первой неудачной попытки.

## Fallback

`spacepayments` никогда не входит в soft pool. Он проверяется и вызывается после отсутствия eligible внешних кандидатов или их отказов. В strict official mode отсутствие/неработоспособность fallback останавливает весь run до выдачи частичного результата.

## Симуляция и calibration

Seeded simulator получает uniform value из SHA-256 (`seed:operation:provider:attempt`), поэтому порядок random calls не влияет на результат. Scripted simulator читает точный outcome по паре operation/provider.

History calibration по умолчанию выключена. При opt-in применяется shrinkage:

`effective = (snapshot × prior_strength + empirical × n) / (prior_strength + n)`

только при `n >= minimum_samples`. История никогда не изменяет hard constraints и не входит в знаменатель текущей очереди.
