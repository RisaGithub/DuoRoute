# frozen_string_literal: true

class RoutingRunsController < ApplicationController
  MAX_UPLOAD = 10 * 1024 * 1024

  before_action :set_run, only: %i[show progress operation download preview]

  def index
    @runs = RoutingRun.recent
  end

  def new
    @defaults = default_inputs
    set_weight_defaults
  end

  def create
    params[:preset] = params[:preset].presence || DuoRoute::DefaultSelection.strategy
    params[:timeout_mode] = params[:timeout_mode].presence || "fallback_on_timeout"
    params[:simulator_mode] = params[:simulator_mode].presence || "history"
    params[:seed] = params[:seed].presence || 42
    providers_text = input_content(:providers_file, :providers_text, default_inputs[:providers])
    operations_text = input_content(:operations_file, :operations_text, default_inputs[:operations])
    config_text = input_content(:config_file, :config_text, default_inputs[:config])
    history_text = params.key?(:history_file) || params.key?(:history_text) ? optional_content(:history_file, :history_text) : default_inputs[:history]
    outcomes_text = optional_content(:outcomes_file, :outcomes_text)
    providers = DuoRoute::Input::Loader.json_string(providers_text, label: "providers upload")
    operations = DuoRoute::Input::Loader.json_string(operations_text, label: "operations upload")
    DuoRoute::Configuration.fail!("strategy", "неизвестная стратегия") unless RoutingRun::PRESETS.include?(params[:preset])
    provider_names = (providers.is_a?(Hash) ? Array(providers["providers"]) : []).filter_map { |provider| provider["payment_system"] if provider.is_a?(Hash) }
    config = StrategySetting.apply(parse_config(config_text), params[:preset], provider_names:)
    config = DuoRoute::Configuration.resolve(config, strategy: params[:preset].presence || DuoRoute::DefaultSelection.strategy, settings: params[:settings].to_s.lines.map(&:strip).reject(&:empty?))
    apply_policy_weights!(config)
    outcomes = outcomes_text.present? ? DuoRoute::Input::Loader.json_string(outcomes_text, label: "outcomes upload") : nil
    history = history_text.present? ? DuoRoute::Input::Loader.csv_string(history_text, label: "history upload") : []
    preview_config = JSON.parse(JSON.generate(config))
    preview_config["routing"] ||= {}
    preview_config["routing"]["timeout_mode"] = params[:timeout_mode]
    preview_config["simulation"] ||= {}
    preview_config["simulation"]["source"] = params[:simulator_mode] == "seeded" ? "provider_snapshot" : params[:simulator_mode].presence || "history"
    runner = DuoRoute::Runner.new(providers_data: providers, operations:, config: preview_config, history:,
      preset: params[:preset], seed: params[:seed], outcomes: params[:simulator_mode] == "scripted" ? outcomes : nil)
    runner.validate!
    config = runner.config
    config["user_configuration"] ||= {}
    config["user_configuration"]["settings"] = params[:settings].to_s.lines.map(&:strip).reject(&:empty?)
    config["user_configuration"]["custom_weights"] = config.dig("presets", params[:preset], "weights") if params[:custom_weights] == "1"
    config["input_metadata"] = { providers: providers_text, operations: operations_text, history: history_text, outcomes: outcomes_text, config: config_text }.to_h do |key, content|
      [ key.to_s, { "filename" => params["#{key}_file"]&.original_filename, "bytes" => content.to_s.bytesize, "sha256" => Digest::SHA256.hexdigest(content.to_s) } ]
    end
    run = RoutingRun.create!(name: params[:name].presence || "Run #{Time.current.strftime('%d.%m %H:%M')}",
      preset: params[:preset], timeout_mode: params[:timeout_mode], simulator_mode: params[:simulator_mode], seed: params[:seed],
      providers_json: JSON.generate(providers), operations_json: JSON.generate(operations), config_json: JSON.generate(config),
      history_csv: history_text, outcomes_json: outcomes && JSON.generate(outcomes), total: operations.length)
    RoutingRunJob.perform_later(run.id)
    redirect_to run_path(run)
  rescue DuoRoute::InputError => e
    @defaults = default_inputs
    set_weight_defaults
    @issues = e.issues
    render :new, status: :unprocessable_entity
  end

  def show; end

  def progress
    render json: { status: @run.status, processed: @run.processed, total: @run.total,
      progress_pct: @run.progress_pct, current_operation: @run.current_operation, last_event: @run.last_event,
      elapsed_seconds: @run.elapsed_seconds, redirect: @run.status == "completed" ? run_path(@run) : nil,
      error: @run.error_message }
  end

  def operation
    @decision = @run.operation_decision(params[:operation_id])
    raise ActiveRecord::RecordNotFound unless @decision
    @operation = @run.operations.find { |item| item["operation_id"] == params[:operation_id] }
  end

  def download
    artifact, filename, type = artifact_data
    send_data artifact, filename:, type:, disposition: "attachment"
  end

  def preview
    content, @filename, type = artifact_data
    @content = if content.blank?
      ""
    elsif type == "application/json"
      JSON.pretty_generate(JSON.parse(content))
    else
      content
    end
    respond_to do |format|
      format.html
      format.json { render json: { filename: @filename, content: @content } }
    end
  end

  private

  def artifact_data
    case params[:artifact]
    when "decisions" then [ @run.decisions_json, "routing_decisions.json", "application/json" ]
    when "report" then [ @run.report_json, "routing_report.json", "application/json" ]
    when "config" then [ DuoRoute.pretty_json(@run.config), "routing_config.json", "application/json" ]
    when "providers" then [ @run.providers_json, "providers.json", "application/json" ]
    when "operations" then [ @run.operations_json, "operations.json", "application/json" ]
    when "history" then [ @run.history_csv.to_s, "operations_history.csv", "text/csv" ]
    when "outcomes" then [ @run.outcomes_json || "{}", "outcomes.json", "application/json" ]
    when "manifest" then [ DuoRoute.pretty_json(@run.manifest), "routing_manifest.json", "application/json" ]
    else raise ActiveRecord::RecordNotFound
    end
  end

  def set_run = @run = RoutingRun.find(params[:id])

  def input_content(file_key, text_key, fallback)
    optional_content(file_key, text_key).presence || fallback
  end

  def optional_content(file_key, text_key)
    upload = params[file_key]
    if upload.blank?
      content = params[text_key].to_s
      raise DuoRoute::InputError, [ DuoRoute::ValidationIssue.new(path: text_key.to_s, code: "file_too_large", message: "лимит #{MAX_UPLOAD} байт") ] if content.bytesize > MAX_UPLOAD
      return content
    end
    raise DuoRoute::InputError, [ DuoRoute::ValidationIssue.new(path: file_key.to_s, code: "file_too_large", message: "лимит #{MAX_UPLOAD} байт") ] if upload.size > MAX_UPLOAD
    upload.read.force_encoding("UTF-8")
  end

  def parse_config(text)
    text = text.to_s
    stripped = text.lstrip
    DuoRoute::Input::Loader.config_string(text, label: "config upload", format: stripped.start_with?("{") ? :json : :yaml)
  end

  def default_inputs
    { providers: Rails.root.join("data/examples/providers.json").read,
      operations: Rails.root.join("data/examples/operations_queue_10.json").read,
      config: Rails.root.join("config/routing/default.yml").read,
      history: Rails.root.join("data/examples/operations_history.csv").read,
      outcomes: Rails.root.join("data/examples/demo_outcomes.json").read }
  end

  def set_weight_defaults
    @strategy_catalog = StrategySetting.catalog
    base = parse_config(@defaults[:config])
    @mode_defaults = %w[balanced custom].to_h do |mode|
      resolved = DuoRoute::Configuration.resolve(StrategySetting.apply(base, mode), strategy: mode)
      [ mode, { "weights" => resolved.dig("presets", mode, "weights") || {}, "parameters" => resolved.slice("provider_overrides") } ]
    end
    parsed = DuoRoute::Configuration.resolve(StrategySetting.apply(base, params[:preset].presence || DuoRoute::DefaultSelection.strategy), strategy: params[:preset].presence || DuoRoute::DefaultSelection.strategy)
    preset = params[:preset].presence || DuoRoute::DefaultSelection.strategy
    @weight_defaults = parsed.dig("presets", preset, "weights") || parsed.dig("presets", "balanced", "weights") || {}
  rescue DuoRoute::InputError
    @weight_defaults = {}
    @mode_defaults = {}
  end

  def apply_policy_weights!(config)
    return unless params[:custom_weights] == "1"

    submitted = params[:policy_weights]
    return unless submitted.respond_to?(:to_unsafe_h)

    allowed = DuoRoute::Validation::InputValidator::POLICY_NAMES
    unknown = submitted.keys - allowed
    DuoRoute::Configuration.fail!("weights", "неизвестные факторы: #{unknown.join(', ')}") if unknown.any?
    weights = submitted.to_unsafe_h.transform_values { |value| Float(value) }
    config["presets"] ||= {}
    config["presets"][params[:preset]] ||= {}
    config["presets"][params[:preset]]["weights"] = weights
  rescue ArgumentError, TypeError
    raise DuoRoute::InputError, [ DuoRoute::ValidationIssue.new(path: "$config.weights", code: "invalid_weight", message: "все веса должны быть числами") ]
  end
end
