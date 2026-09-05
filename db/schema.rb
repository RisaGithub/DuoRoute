# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_04_090000) do
  create_table "routing_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.text "config_json", null: false
    t.datetime "created_at", null: false
    t.string "current_operation"
    t.text "decisions_json"
    t.text "error_message"
    t.text "history_csv"
    t.string "last_event"
    t.text "manifest_json"
    t.string "name", null: false
    t.text "operations_json", null: false
    t.text "outcomes_json"
    t.string "preset", default: "balanced", null: false
    t.integer "processed", default: 0, null: false
    t.text "providers_json", null: false
    t.text "report_json"
    t.integer "seed", default: 42, null: false
    t.string "simulator_mode", default: "seeded", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "timeout_mode", default: "fallback_on_timeout", null: false
    t.integer "total", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_routing_runs_on_created_at"
    t.index ["status"], name: "index_routing_runs_on_status"
  end
end
