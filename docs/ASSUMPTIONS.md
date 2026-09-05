# Допущения и разрешение неоднозначностей

Приоритет: письменный Telegram → `описание.docx`/criteria → public validator → устный Q&A → sample shape.

1. `traffic_percentage` считается по итоговому `selected_provider` на горизонте текущей очереди. Это прямой письменный ответ организаторов. History не добавляется в знаменатель.
2. Обработка строго online, без look-ahead. При равном `created_at` сохраняется входной порядок.
3. Границы hard min/max включительны; `nil` numeric limit — unlimited; пустой `banks` — unrestricted. Это согласуется с validator.
4. В official config timeout default — `fallback_on_timeout`, поскольку именно это прямо написано в ТЗ. Устное production-пояснение реализовано отдельным `hold_until_status`.
5. Reservation происходит непосредственно перед вызовом simulator. Reject/cancel освобождает in-progress, но RPM остаётся фактом попытки. Approved увеличивает daily и освобождает in-progress.
6. В `hold_until_status` late rejected применяет компенсацию с текущего момента и продолжает cascade; прошлые decisions не переигрываются, как рекомендовано Q&A.
7. `spacepayments` — специальный self-provider. Он не soft-scored и используется после внешнего pool. Его operational status/requisites и применимые hard limits всё равно валидируются.
8. Даже если итоговый fallback отклоняет выплату, формат сохраняет его как единственную selected attempt и реальный simulated result. Это обозначает финальный маршрут/ответ, а не гарантированный успех.
9. Optional policy field отсутствует → policy disabled для кандидата; оно не интерпретируется как zero. Overrides — универсальный config-механизм.
10. Для ранжирования provider `conversion_24h` каноничен; вероятности симуляции по умолчанию считаются из истории. Blended conversion — только opt-in, beta-binomial-подобный weighted shrinkage без ML.
11. `latency_sec` считается обязательным из-за формата примера и явного требования пользователя, хотя public validator его не проверяет.
12. `daily_approved_amount` меняется только при approved или подтверждённом late approval. Финальная count/volume distribution включает selected provider независимо от simulated result согласно формулировке про «кто реально принял заявку».
13. Exact simultaneous concurrency не моделируется в batch: очередь линеаризована. State object выделен так, чтобы production adapter мог сериализовать reserve operation.
14. Web cancellation не реализована: in-process job на коротком public batch завершается быстрее безопасного round-trip. UI не показывает ложную кнопку отмены.
15. Runtime duration наблюдаема в report manifest/web elapsed; она по природе не является детерминированной частью стратегии. Decisions остаются byte-stable.
