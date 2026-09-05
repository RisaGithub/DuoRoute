# frozen_string_literal: true

class RoutingRunJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = RoutingRun.find(run_id)
    run.update!(status: "running", started_at: Time.current, last_event: "Проверка входных данных")
    config = run.config
    config["routing"] ||= {}
    config["routing"]["timeout_mode"] = run.timeout_mode
    history = run.history_csv.present? ? DuoRoute::Input::Loader.csv_string(run.history_csv) : []
    runner = DuoRoute::Runner.new(providers_data: run.providers, operations: run.operations, config:, history:,
      preset: run.preset, seed: run.seed, outcomes: run.simulator_mode == "scripted" ? run.outcomes : nil,
      progress: ->(done, total, operation) { update_progress(run, done, total, operation) })
    result = runner.call
    run.update!(status: "completed", processed: run.total, current_operation: nil, last_event: "Артефакты готовы",
      decisions_json: JSON.generate(result.decisions), report_json: JSON.generate(result.report),
      manifest_json: JSON.generate(result.manifest), completed_at: Time.current)
  rescue StandardError => e
    run&.update(status: "failed", error_message: safe_error(e), last_event: "Запуск остановлен",
      completed_at: Time.current)
  end

  private

  def update_progress(run, done, total, operation)
    run.update_columns(processed: done, total:, current_operation: operation,
      last_event: operation ? "Маршрутизация #{operation}" : "Формирование отчёта", updated_at: Time.current)
  end

  def safe_error(error)
    error.message.gsub(/\b7\d{10}\b/, "+7••• •••-••-••").first(2_000)
  end
end
