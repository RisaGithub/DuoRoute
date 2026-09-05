# frozen_string_literal: true

class RoutingRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  PRESETS = %w[balanced count_share volume_share cascade conversion_first load_safe turnover_commitment economy_first].freeze

  validates :name, :status, :preset, :timeout_mode, :simulator_mode, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :preset, inclusion: { in: PRESETS }

  scope :recent, -> { order(created_at: :desc) }

  def providers = parse(providers_json, {})
  def operations = parse(operations_json, [])
  def config = parse(config_json, {})
  def outcomes = parse(outcomes_json, nil)
  def decisions = parse(decisions_json, [])
  def report = parse(report_json, {})
  def manifest = parse(manifest_json, {})

  def operation_decision(operation_id)
    decisions.find { |decision| decision["operation_id"] == operation_id }
  end

  def progress_pct
    total.zero? ? 0 : (processed.to_f / total * 100).round(1)
  end

  def elapsed_seconds
    return 0 unless started_at
    ((completed_at || Time.current) - started_at).round(2)
  end

  private

  def parse(value, fallback)
    value.present? ? JSON.parse(value) : fallback
  rescue JSON::ParserError
    fallback
  end
end
