class CreateStrategySettings < ActiveRecord::Migration[8.1]
  def change
    create_table :strategy_settings do |t|
      t.string :name, null: false
      t.json :provider_overrides, null: false, default: {}
      t.timestamps
    end
    add_index :strategy_settings, :name, unique: true
  end
end
