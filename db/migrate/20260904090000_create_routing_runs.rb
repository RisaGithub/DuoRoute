class CreateRoutingRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :routing_runs do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "queued"
      t.string :preset, null: false, default: "balanced"
      t.string :timeout_mode, null: false, default: "fallback_on_timeout"
      t.string :simulator_mode, null: false, default: "seeded"
      t.integer :seed, null: false, default: 42
      t.integer :processed, null: false, default: 0
      t.integer :total, null: false, default: 0
      t.string :current_operation
      t.string :last_event
      t.text :error_message
      t.text :providers_json, null: false
      t.text :operations_json, null: false
      t.text :history_csv
      t.text :config_json, null: false
      t.text :outcomes_json
      t.text :decisions_json
      t.text :report_json
      t.text :manifest_json
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :routing_runs, :status
    add_index :routing_runs, :created_at
  end
end
