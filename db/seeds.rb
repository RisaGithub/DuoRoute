# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
public_run = RoutingRun.find_or_initialize_by(name: "Public demo · balanced")
public_run.assign_attributes(status: "queued", preset: "balanced", seed: 42,
  timeout_mode: "fallback_on_timeout", simulator_mode: "scripted",
  providers_json: Rails.root.join("data/examples/providers.json").read,
  operations_json: Rails.root.join("data/examples/operations_queue_10.json").read,
  history_csv: Rails.root.join("data/examples/operations_history.csv").read,
  config_json: JSON.generate(DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s)),
  outcomes_json: Rails.root.join("data/examples/demo_outcomes.json").read,
  decisions_json: nil, report_json: nil, manifest_json: nil, processed: 0, total: 10,
  started_at: nil, completed_at: nil, error_message: nil)
public_run.save!
RoutingRunJob.perform_now(public_run.id)
