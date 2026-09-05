# frozen_string_literal: true

require "test_helper"

class ReportGeneratorTest < ActiveSupport::TestCase
  test "report math distributions rounding and evidence based recommendations" do
    providers = providers_data
    operations = [ operation("one", amount: 500), operation("two", amount: 1500) ]
    outcomes = { "one:alpha" => "approved", "two:spacepayments" => "approved" }
    # The second operation exceeds alpha hard max, so fallback is legitimate.
    result = DuoRoute::Runner.new(providers_data: providers, operations:, config: config, outcomes: { "outcomes" => outcomes }, preset: "balanced").call
    report = result.report
    assert_equal 2, report["total_operations"]
    assert_equal 2000, report["total_amount"]
    assert_equal 50.0, report.dig("distribution", "alpha", "share_pct")
    assert_equal 25.0, report.dig("volume_distribution", "alpha", "share_pct")
    assert_equal 50.0, report["fallback_rate_pct"]
    assert report["recommendation_details"].all? { |item| item["evidence"].present? && item["proposed_action"].present? }
    assert_empty DuoRoute::Reporting::OutputValidator.new.report(report, expected_total: 2)
  end

  test "history analyzer and opt in shrinkage calibration are transparent" do
    rows = 20.times.map do |index|
      { "payment_system" => "alpha", "status" => index < 10 ? "approved" : "rejected", "amount" => "100", "latency_sec" => "20" }
    end
    analyzer = DuoRoute::Reporting::HistoryAnalyzer.new(rows)
    assert_equal 0.5, analyzer.call.dig("alpha", "empirical_conversion")
    calibrated = analyzer.calibrated([ provider ], minimum_samples: 20, prior_strength: 20).first
    assert_in_delta 0.65, calibrated["effective_conversion"]
    assert_equal 20, calibrated.dig("conversion_calibration", "samples")
  end

  test "generator is reproducible and invalid scenario is intentionally invalid" do
    one = DuoRoute::Generators::Scenario.new(name: "normal", operations: 20, providers: 3, seed: 42).call
    two = DuoRoute::Generators::Scenario.new(name: "normal", operations: 20, providers: 3, seed: 42).call
    assert_equal JSON.generate(one), JSON.generate(two)
    invalid = DuoRoute::Generators::Scenario.new(name: "invalid_data", operations: 4, providers: 3, seed: 42).call
    issues = DuoRoute::Validation::InputValidator.new.call(providers_data: invalid["providers"], operations: invalid["operations"], config: config)
    assert issues.any?
  end

  test "randomized invariant run never selects ineligible external or early fallback" do
    bundle = DuoRoute::Generators::Scenario.new(name: "stress", operations: 300, providers: 8, seed: 818).call
    result = DuoRoute::Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], config: full_config,
      outcomes: bundle["outcomes"], preset: "balanced", seed: 818).call
    result.decisions.each do |decision|
      selected = decision["selected_provider"]
      if selected == "spacepayments"
        assert_empty decision["eligible_pool"]
      else
        assert decision.dig("constraint_matrix", selected, "eligible"), "#{decision['operation_id']} selected blocked #{selected}"
      end
      decision["state_after"].each_value do |state|
        assert_operator state["in_progress_count"], :>=, 0
        assert_operator state["in_progress_amount"], :>=, 0
      end
    end
  end

  private

  def full_config
    DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s)
  end
end
