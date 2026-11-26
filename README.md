# DuoRoute

DuoRoute получает очередь выплат, проверяет доступность провайдеров, выбирает лучший вариант по заданной стратегии, переходит к следующему при отказе и сохраняет объяснение каждого решения. Проект команды DuoTech для Hack.Genesis 2026, кейс «Умный роутинг выплат».

## Вход

JSON со состоянием провайдеров и очередью операций, настройки YAML/JSON и история CSV. Для точного демонстрационного сценария можно добавить ответы провайдеров `outcomes.json`.

## Обработка

Программа последовательно проверяет обязательные ограничения, оценивает допустимых провайдеров по одной из семи стратегий или их комбинации и обновляет состояние после попыток. Ответы моделируются локально; реальные выплаты не отправляются. CLI и Web используют одно Ruby-ядро.

## Выход

`routing_decisions.json` содержит решения и причины по каждой операции; `routing_report.json` — распределение, успешность, лимиты и рекомендации. Рядом сохраняются конфигурация и Manifest — параметры и контрольные суммы для повторения расчёта.

## Быстрый запуск Web

Нужны Ruby **3.4.10** через rbenv, Bundler и SQLite. Установка и исправление системной Ruby описаны в [CLI](docs/CLI.md#installation).

```bash
git clone https://github.com/RisaGithub/DuoRoute.git
cd DuoRoute
bin/setup --skip-server
bin/dev -b 127.0.0.1 -p 3000
```

Откройте <http://localhost:3000>. Подготовка добавляет готовый публичный пример.

## Веб-интерфейс на скриншотах

На скриншотах — веб-интерфейс DuoRoute с демонстрационными данными. Нажмите на изображение, чтобы открыть его в полном размере.

**Дашборд: успешность, резерв и распределение выплат**

[![Дашборд: успешность, резерв и распределение выплат](docs/readme-screenshots/duoroute-03-dashboard.webp)](docs/readme-screenshots/duoroute-03-dashboard.webp)

**Вклад стратегий в оценку и матрица ограничений**

[![Вклад стратегий в оценку и матрица ограничений](docs/readme-screenshots/duoroute-16-decision.webp)](docs/readme-screenshots/duoroute-16-decision.webp)

**Сравнение стратегий: успешность, резерв и задержка**

[![Сравнение стратегий: успешность, резерв и задержка](docs/readme-screenshots/duoroute-18-comparison.webp)](docs/readme-screenshots/duoroute-18-comparison.webp)

<details>
<summary>Аналитика и карточки провайдеров</summary>

**План и факт по сумме и количеству, достижимость целей**

[![План и факт по сумме и количеству, достижимость целей](docs/readme-screenshots/duoroute-04-goals.webp)](docs/readme-screenshots/duoroute-04-goals.webp)

**Провайдеры: оборот, загрузка и лимиты**

[![Провайдеры: оборот, загрузка и лимиты](docs/readme-screenshots/duoroute-05-providers.webp)](docs/readme-screenshots/duoroute-05-providers.webp)

**Vipay: показатели и ограничения**

[![Vipay: показатели и ограничения](docs/readme-screenshots/duoroute-06-vipay.webp)](docs/readme-screenshots/duoroute-06-vipay.webp)

**Payflow: показатели и ограничения**

[![Payflow: показатели и ограничения](docs/readme-screenshots/duoroute-07-payflow.webp)](docs/readme-screenshots/duoroute-07-payflow.webp)

**Quickpay: показатели и ограничения**

[![Quickpay: показатели и ограничения](docs/readme-screenshots/duoroute-08-quickpay.webp)](docs/readme-screenshots/duoroute-08-quickpay.webp)

**Spacepayments: резервный провайдер**

[![Spacepayments: резервный провайдер](docs/readme-screenshots/duoroute-09-spacepayments.webp)](docs/readme-screenshots/duoroute-09-spacepayments.webp)

</details>

<details>
<summary>Запуски, отчёты и разбор маршрута</summary>

**История запусков**

[![История запусков](docs/readme-screenshots/duoroute-10-runs.webp)](docs/readme-screenshots/duoroute-10-runs.webp)

**Новый запуск: веса, симуляция и загрузка файлов**

[![Новый запуск: веса, симуляция и загрузка файлов](docs/readme-screenshots/duoroute-11-new-run.webp)](docs/readme-screenshots/duoroute-11-new-run.webp)

**Результат запуска: метрики и решения по выплатам**

[![Результат запуска: метрики и решения по выплатам](docs/readme-screenshots/duoroute-12-run.webp)](docs/readme-screenshots/duoroute-12-run.webp)

**Рекомендации и параметры воспроизводимости**

[![Рекомендации и параметры воспроизводимости](docs/readme-screenshots/duoroute-13-reproducibility.webp)](docs/readme-screenshots/duoroute-13-reproducibility.webp)

**Предпросмотр отчёта JSON**

[![Предпросмотр отчёта JSON](docs/readme-screenshots/duoroute-14-report.webp)](docs/readme-screenshots/duoroute-14-report.webp)

**Каскад попыток и переход на резерв**

[![Каскад попыток и переход на резерв](docs/readme-screenshots/duoroute-15-fallback.webp)](docs/readme-screenshots/duoroute-15-fallback.webp)

</details>

<details>
<summary>Каталог стратегий и генератор данных</summary>

**Каталог семи стратегий**

[![Каталог семи стратегий](docs/readme-screenshots/duoroute-17-strategies.webp)](docs/readme-screenshots/duoroute-17-strategies.webp)

**Генератор сценариев и предпросмотр тестового набора**

[![Генератор сценариев и предпросмотр тестового набора](docs/readme-screenshots/duoroute-19-generator.webp)](docs/readme-screenshots/duoroute-19-generator.webp)

</details>

<details>
<summary>Страница продукта, архитектура и документация</summary>

**Страница продукта**

[![Страница продукта](docs/readme-screenshots/duoroute-01-product.webp)](docs/readme-screenshots/duoroute-01-product.webp)

**Архитектура и документация**

[![Архитектура и документация](docs/readme-screenshots/duoroute-02-architecture.webp)](docs/readme-screenshots/duoroute-02-architecture.webp)

**Встроенная документация алгоритма**

[![Встроенная документация алгоритма](docs/readme-screenshots/duoroute-20-documentation.webp)](docs/readme-screenshots/duoroute-20-documentation.webp)

**Страница продукта целиком**

[![Страница продукта целиком](docs/readme-screenshots/duoroute-21-product-full.webp)](docs/readme-screenshots/duoroute-21-product-full.webp)

</details>

## Быстрый запуск CLI

Из корня подготовленного проекта:

```bash
bin/router demo --seed 42
ruby script/validate_10.rb routing_decisions.json
```

Это публичная демонстрация с заранее заданными ответами. CLI работает без Web и базы данных.

## Документация

- [CLI](docs/CLI.md) — команды, входные файлы, настройки и финальный запуск.
- [Web-интерфейс](docs/WEB.md) — страницы и работа через браузер.
- [Соответствие критериям](docs/CRITERIA_COMPLIANCE.md) — как выполнен каждый пункт оценки.
- [Архитектура](docs/ARCHITECTURE.md) — устройство проекта.
- [Алгоритм](docs/ALGORITHM.md) — правила выбора провайдера и формулы.

## Проверка готовности

```bash
bin/router readiness
```

`selected_provider` содержит итогового провайдера после каскада и fallback; `attempts` — полную последовательность попыток. Пользовательские стратегии комбинируют существующие мягкие политики и не отключают обязательные ограничения. Отсутствующая цель не равна нулевой. `balanced` — проверенная безопасная конфигурация по умолчанию в пределах исследованных сценариев, без гарантии математической оптимальности.

Лицензия — MIT; [сторонние компоненты](THIRD_PARTY_NOTICES.md).
