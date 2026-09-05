# frozen_string_literal: true

class RoutingRunsController < ApplicationController
  MAX_UPLOAD = 10 * 1024 * 1024

  before_action :set_run, only: %i[show progress operation download]

  def index
    @runs = RoutingRun.recent.limit(50)
  end

  def new
    @defaults = default_inputs
    set_weight_defaults
  end

  def create
    providers_text = input_content(:providers_file, :providers_text, default_inputs[:providers])
    operations_text = input_content(:operations_file, :operations_text, default_inputs[:operations])
    config_text = input_content(:config_file, :config_text, default_inputs[:config])
    history_text = optional_content(:history_file, :history_text)
    outcomes_text = optional_content(:outcomes_file, :outcomes_text)
    providers = DuoRoute::Input::Loader.json_string(providers_text, label: "providers upload")
    operations = DuoRoute::Input::Loader.json_string(operations_text, label: "operations upload")
    config = parse_config(config_text)
    apply_policy_weights!(config)
    outcomes = outcomes_text.present? ? DuoRoute::Input::Loader.json_string(outcomes_text, label: "outcomes upload") : nil
    history = history_text.present? ? DuoRoute::Input::Loader.csv_string(history_text, label: "history upload") : []
    preview_config = JSON.parse(JSON.generate(config))
    preview_config["routing"] ||= {}
    preview_config["routing"]["timeout_mode"] = params[:timeout_mode]
    DuoRoute::Runner.new(providers_data: providers, operations:, config: preview_config, history:,
      preset: params[:preset], seed: params[:seed], outcomes: params[:simulator_mode] == "scripted" ? outcomes : nil).validate!
    run = RoutingRun.create!(name: params[:name].presence || "Run #{Time.current.strftime('%d.%m %H:%M')}",
      preset: params[:preset], timeout_mode: params[:timeout_mode], simulator_mode: params[:simulator_mode], seed: params[:seed],
      providers_json: JSON.generate(providers), operations_json: JSON.generate(operations), config_json: JSON.generate(config),
      history_csv: history_text, outcomes_json: outcomes && JSON.generate(outcomes), total: operations.length)
    RoutingRunJob.perform_later(run.id)
    redirect_to run_path(run)
  rescue DuoRoute::InputError => e
    @defaults = { providers: providers_text, operations: operations_text, config: config_text, history: history_text, outcomes: outcomes_text }
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
    artifact, filename, type = case params[:artifact]
    when "decisions" then [ @run.decisions_json, "routing_decisions.json", "application/json" ]
    when "report" then [ @run.report_json, "routing_report.json", "application/json" ]
    when "config" then [ DuoRoute.pretty_json(@run.config), "routing_config.json", "application/json" ]
    when "manifest" then [ DuoRoute.pretty_json(@run.manifest), "routing_manifest.json", "application/json" ]
    else raise ActiveRecord::RecordNotFound
    end
    send_data artifact, filename:, type:, disposition: "attachment"
  end

  private

  def set_run = @run = RoutingRun.find(params[:id])

  def input_content(file_key, text_key, fallback)
    optional_content(file_key, text_key).presence || fallback
  end

  def optional_content(file_key, text_key)
    upload = params[file_key]
    return params[text_key].to_s if upload.blank?
    raise DuoRoute::InputError, [ DuoRoute::ValidationIssue.new(path: file_key.to_s, code: "file_too_large", message: "лимит #{MAX_UPLOAD} байт") ] if upload.size > MAX_UPLOAD
    upload.read.force_encoding("UTF-8")
  end

  def parse_config(text)
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
    parsed = parse_config(@defaults[:config])
    preset = params[:preset].presence || "balanced"
    @weight_defaults = parsed.dig("presets", preset, "weights") || parsed.dig("presets", "balanced", "weights") || {}
  rescue DuoRoute::InputError
    @weight_defaults = {}
  end

  def apply_policy_weights!(config)
    return unless params[:custom_weights] == "1"

    submitted = params[:policy_weights]
    return unless submitted.respond_to?(:to_unsafe_h)

    allowed = DuoRoute::Validation::InputValidator::POLICY_NAMES
    weights = submitted.to_unsafe_h.slice(*allowed).transform_values { |value| Float(value) }
    config["presets"] ||= {}
    config["presets"][params[:preset]] ||= {}
    config["presets"][params[:preset]]["weights"] = weights
  rescue ArgumentError
    raise DuoRoute::InputError, [ DuoRoute::ValidationIssue.new(path: "$config.weights", code: "invalid_weight", message: "все веса должны быть числами") ]
  end
end
