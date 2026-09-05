# Stopcode checklist

До получения очереди `_test` не создавать файлы с финальными именами.

1. Положить настоящий файл организаторов в корень как `operations_queue_test.json`. Не переименовывать public queue.
2. Убедиться, что `data/providers.json` — актуальный выданный snapshot. Если организаторы прислали новый providers, заменить только этот файл осознанно и сохранить исходник отдельно вне `_test` outputs.
3. Проверить working tree и свободное место.
4. Запустить strict validation:

   ```bash
   bin/router validate --providers data/providers.json \
     --operations operations_queue_test.json \
     --config config/routing/final.yml --preset balanced
   ```

5. Если есть официальный deterministic outcomes-файл, добавить `--outcomes PATH`; иначе сохранить согласованный seed 42.
6. Создать финальные artifacts одной командой:

   ```bash
   bin/router final --operations operations_queue_test.json \
     --providers data/providers.json --config config/routing/final.yml \
     --preset balanced --seed 42
   ```

7. Проверить точные имена и coverage:

   ```bash
   ls -l routing_decisions_test.json routing_report_test.json
   ruby -rjson -e 'q=JSON.parse(File.read("operations_queue_test.json")); d=JSON.parse(File.read("routing_decisions_test.json")); abort "coverage mismatch" unless q.map{|x|x["operation_id"]}.sort == d.map{|x|x["operation_id"]}.sort; puts "coverage ok: #{d.size}"'
   ```

8. Запустить предоставленный финальный validator организаторов без модификации, если он выдан.
9. Просмотреть первые/последние decisions, fallback rate, errors, target exceptions и reproducibility digests.
10. Запустить `bin/rails test` и `git diff --check`.
11. Проверить, что оба JSON находятся в корне ветки `main`; коммит и push выполняет член команды вручную.

Защита от ошибки: `final` отвергает любой basename кроме `operations_queue_test.json`, не пишет partial output при input/output validation error, не может перезаписать вход и создаёт temp-файлы перед rename. Старые outputs не трогаются до успешной полной генерации.
