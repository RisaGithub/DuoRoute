# frozen_string_literal: true

class StrategiesController < ApplicationController
  def show
    @strategies = StrategySetting.catalog
    @config = routing_config
  end

  def compare
    @strategies = StrategySetting.catalog
    @config = routing_config
    if request.get? && !params.key?(:presets) && !params.key?(:seed)
      build_comparison(@strategies.keys, 42, "defaults")
      return render :show
    end
    @comparison_submitted = true
    presets = Array(params[:presets]).intersection(@strategies.keys)
    seed = Integer(params[:seed].presence || 42, exception: false)
    if presets.length < 2 || seed.nil? || seed.negative?
      @errors = [ "Выберите минимум две стратегии и укажите целый неотрицательный seed." ]
      return render :show, status: :unprocessable_entity
    end
    build_comparison(presets, seed, params[:source] == "saved" ? "saved" : "defaults")
    render :show
  rescue DuoRoute::InputError => e
    @errors = e.issues.map { |issue| "#{issue.path}: #{issue.message}" }
    render :show, status: :unprocessable_entity
  end

  def update
    @strategies = StrategySetting.catalog
    raise ActiveRecord::RecordNotFound unless @strategies.key?(params[:name])
    setting = StrategySetting.find_or_initialize_by(name: params[:name])
    submitted = params[:provider_overrides]
    values = submitted.is_a?(ActionController::Parameters) ? submitted.to_unsafe_h : {}
    setting.provider_overrides = values.transform_values do |fields|
      fields.is_a?(Hash) ? fields.transform_values { |value| value.blank? ? nil : Float(value, exception: false) || value } : fields
    end
    if setting.save
      redirect_to strategies_path(anchor: params[:name]), notice: "Параметры стратегии сохранены"
    else
      @errors = setting.errors.full_messages
      if setting.provider_overrides.is_a?(Hash) && setting.provider_overrides.values.all? { |fields| fields.is_a?(Hash) }
        @strategies[params[:name]]["parameters"]["provider_overrides"] = setting.provider_overrides
      end
      render :show, status: :unprocessable_entity
    end
  end

  def reset
    raise ActiveRecord::RecordNotFound unless DuoRoute::StrategyCatalog.all.key?(params[:name])
    StrategySetting.find_by(name: params[:name])&.destroy!
    redirect_to strategies_path(anchor: params[:name]), notice: "Восстановлены исходные параметры стратегии"
  end

  private

  def build_comparison(presets, seed, source)
    @comparison_seed = seed
    @comparison_source = source
    @comparison_catalog = source == "saved" ? StrategySetting.catalog : DuoRoute::StrategyCatalog.all
    providers = DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/providers.json").to_s)
    operations = DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/operations_queue_10.json").to_s)
    config = routing_config
    config["simulation"] ||= {}
    config["simulation"]["source"] = "provider_snapshot"
    @comparison = presets.map do |preset|
      resolved = DuoRoute::Configuration.merge(@comparison_catalog.fetch(preset).fetch("parameters"), config)
      result = DuoRoute::Runner.new(providers_data: providers, operations:, config: resolved, preset:, seed:).call
      { name: preset, report: result.report }
    end.sort_by do |row|
      report = row[:report]
      [ -report["approval_rate_pct"].to_f, report["fallback_rate_pct"].to_f, report["average_latency_sec"].to_f, row[:name] ]
    end
    @best_strategy = @comparison.first
    @analysis = @comparison.find { |row| row[:name] == params[:focus] } || @best_strategy
  end

  def routing_config = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s).merge("presets" => @strategies.transform_values { |entry| entry.slice("weights", "policy_priorities") })
end
