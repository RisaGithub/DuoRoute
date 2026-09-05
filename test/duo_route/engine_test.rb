# frozen_string_literal: true

require "test_helper"

class EngineTest < ActiveSupport::TestCase
  test "operations are ordered by created_at with stable input order for ties" do
    operations = [ operation("late", created_at: "2026-07-30T09:06:00+03:00"), operation("tie_a"), operation("tie_b") ]
    result = run_with(operations:, outcomes: default_outcomes(operations))
    assert_equal %w[tie_a tie_b late], result.decisions.map { |decision| decision["operation_id"] }
  end

  test "reject rolls back and cascades to next external provider" do
    providers = two_providers
    outcomes = { "op_1:alpha" => { "result" => "rejected", "latency_sec" => 4 },
      "op_1:beta" => { "result" => "approved", "latency_sec" => 9 } }
    result = run_with(providers:, outcomes:)
    decision = result.decisions.first
    assert_equal "beta", decision["selected_provider"]
    assert_equal %w[provider_rejected highest_combined_score], decision["attempts"].select { |a| a.key?("result") }.map { |a| a["reason"] }
    assert_equal 0, decision.dig("state_after", "alpha", "in_progress_count")
    assert_equal 1500, decision.dig("state_after", "beta", "daily_approved_amount")
  end

  test "fallback is selected only after every external candidate rejects" do
    providers = two_providers
    outcomes = { "op_1:alpha" => "rejected", "op_1:beta" => "rejected", "op_1:spacepayments" => "approved" }
    decision = run_with(providers:, outcomes:).decisions.first
    assert_equal "spacepayments", decision["selected_provider"]
    assert decision["fallback_used"]
    assert_equal %w[alpha beta spacepayments], decision["attempts"].select { |a| a.key?("result") }.map { |a| a["provider"] }
  end

  test "fallback on timeout releases reservation and tries next" do
    providers = two_providers
    outcomes = { "op_1:alpha" => { "result" => "expired", "latency_sec" => 300 }, "op_1:beta" => "approved" }
    decision = run_with(providers:, outcomes:, timeout: "fallback_on_timeout").decisions.first
    assert_equal "beta", decision["selected_provider"]
    assert_equal "provider_expired", decision["attempts"].find { |a| a["provider"] == "alpha" }["reason"]
    assert_equal 0, decision.dig("state_after", "alpha", "in_progress_count")
  end

  test "hold until status keeps provider and commits late approval" do
    providers = two_providers
    outcomes = { "op_1:alpha" => { "result" => "expired", "latency_sec" => 300, "status_check_result" => "approved" } }
    decision = run_with(providers:, outcomes:, timeout: "hold_until_status").decisions.first
    assert_equal "alpha", decision["selected_provider"]
    assert_equal "expired", decision["simulated_result"]
    assert_equal "approved", decision["status_check_result"]
    assert_equal 1500, decision.dig("state_after", "alpha", "daily_approved_amount")
  end

  test "hold until rejected status releases and cascades" do
    providers = two_providers
    outcomes = { "op_1:alpha" => { "result" => "expired", "status_check_result" => "rejected" }, "op_1:beta" => "approved" }
    decision = run_with(providers:, outcomes:, timeout: "hold_until_status").decisions.first
    assert_equal "beta", decision["selected_provider"]
    assert_equal "provider_expired_status_rejected", decision["attempts"].find { |a| a["provider"] == "alpha" }["reason"]
  end

  test "unavailable fallback aborts official run" do
    bad_fallback = provider("spacepayments", status: "paused", traffic_percentage: 0, limit_amount_min: nil, limit_amount_max: nil)
    assert_raises(DuoRoute::InputError) { run_with(providers: providers_data([ provider ], fallback: bad_fallback), outcomes: {}) }
  end

  test "hard failures and ranking form complete audit and exact required shape" do
    blocked = provider("blocked", status: "paused", traffic_percentage: 50)
    alpha = provider("alpha", traffic_percentage: 50)
    result = run_with(providers: providers_data([ blocked, alpha ]), outcomes: { "op_1:alpha" => "approved" })
    decision = result.decisions.first
    %w[operation_id selected_provider attempts simulated_result latency_sec].each { |key| assert decision.key?(key) }
    assert_equal "provider_inactive", decision["attempts"].find { |a| a["provider"] == "blocked" }["reason"]
    assert_equal 10, decision.dig("constraint_matrix", "blocked", "checks").length
    assert_empty DuoRoute::Reporting::OutputValidator.new.decisions(result.decisions, operation_ids: [ "op_1" ])
  end

  private

  def two_providers
    alpha = provider("alpha", traffic_percentage: 50, priority: 1)
    beta = provider("beta", traffic_percentage: 50, priority: 2)
    providers_data([ alpha, beta ])
  end

  def default_outcomes(operations)
    operations.to_h { |item| [ "#{item['operation_id']}:alpha", "approved" ] }
  end

  def run_with(providers: providers_data, operations: [ operation ], outcomes:, timeout: "fallback_on_timeout")
    DuoRoute::Runner.new(providers_data: providers, operations:, config: config({ "cascade" => 1 }, timeout:),
      preset: "balanced", outcomes: { "outcomes" => outcomes, "default" => { "result" => "approved", "latency_sec" => 10 } }).call
  end
end
