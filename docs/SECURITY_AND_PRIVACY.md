# Security и privacy

- Routing core, tests, demo и UI assets работают без сетевых вызовов, CDN, telemetry и analytics.
- Web upload ограничен 10 МБ до чтения. Контроллер передаёт только содержимое upload/text; пользовательский параметр никогда не используется как filesystem path.
- JSON разбирается `JSON.parse`, CSV — стандартным parser, YAML — `YAML.safe_load` без aliases/classes/symbols. Вход не исполняется.
- Strict mode собирает все ошибки и не выдаёт частичный конкурсный результат.
- Rails parameter filter скрывает payout requisites, phones и полные input textareas. UI маскирует телефон; job sanitizes phone-like fragments в error message.
- Нет credentials, внешних API, пользовательских аккаунтов или секретов. `config/master.key` создан Rails локально и исключён `.gitignore`.
- SQLite содержит локальные run payloads. Для удаления истории оператор удаляет соответствующую локальную базу или строки; автоматической внешней репликации нет.
- Downloads выбираются из закрытого allow-list (`decisions`, `report`, `config`, `manifest`), поэтому path traversal отсутствует.
- `spacepayments` проверяется на operational availability; сломанный fallback останавливает run.
- Vendored Chart.js 4.4.7 распространяется по MIT. CSP может быть включён стандартным Rails initializer; inline style widths используются только из рассчитанных чисел и escaped ERB.

Остаточное ограничение: development Active Job `:async` живёт в процессе. При аварийном завершении процесса queued/running job не возобновляется автоматически; сохранённые completed runs не повреждаются. Для локального demo это осознанный отказ от Redis/обязательной инфраструктуры.
