# frozen_string_literal: true

class GeneratorsController < ApplicationController
  def show
    @defaults = { scenario: "normal", operations: 100, providers: 4, seed: 42 }
  end

  def create
    @defaults = { scenario: params[:scenario], operations: params[:operations], providers: params[:providers], seed: params[:seed] }
    issues = { operations: 1..20000, providers: 1..50, seed: 0.. }.filter_map do |key, range|
      value = Integer(params[key].to_s, exception: false)
      next if value && range.cover?(value)
      DuoRoute::ValidationIssue.new(path: key.to_s, code: "invalid_parameter", message: "введите целое число в диапазоне #{range}")
    end
    raise DuoRoute::InputError, issues if issues.any?
    @defaults = @defaults.merge(@defaults.except(:scenario).transform_values(&:to_i))
    @bundle = DuoRoute::Generators::Scenario.new(name: @defaults[:scenario], operations: @defaults[:operations],
      providers: @defaults[:providers], seed: @defaults[:seed]).call
    case params[:commit_action]
    when "download"
      send_data DuoRoute.pretty_json(@bundle), filename: "duoroute_#{@defaults[:scenario]}_bundle.json", type: "application/json"
    when "run"
      routing_config = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s)
      DuoRoute::Runner.new(providers_data: @bundle["providers"], operations: @bundle["operations"],
        config: routing_config, preset: DuoRoute::DefaultSelection.strategy, seed: @defaults[:seed], outcomes: @bundle["outcomes"]).validate!
      run = RoutingRun.create!(name: "Generated #{@defaults[:scenario]}", preset: DuoRoute::DefaultSelection.strategy, seed: @defaults[:seed],
        timeout_mode: "fallback_on_timeout", simulator_mode: "scripted", providers_json: JSON.generate(@bundle["providers"]),
        operations_json: JSON.generate(@bundle["operations"]), history_csv: history_csv(@bundle["history"]),
        config_json: JSON.generate(routing_config), outcomes_json: JSON.generate(@bundle["outcomes"]), total: @bundle["operations"].length)
      RoutingRunJob.perform_later(run.id)
      redirect_to run_path(run)
    else
      render :show
    end
  rescue DuoRoute::InputError => e
    @issues = e.issues
    render :show, status: :unprocessable_entity
  end

  private

  def history_csv(rows)
    CSV.generate do |csv|
      csv << %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
      rows.each { |row| csv << row }
    end
  end
end
