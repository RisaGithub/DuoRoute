# frozen_string_literal: true

require "test_helper"

class PoliciesTest < ActiveSupport::TestCase
  def setup
    @alpha = provider("alpha", traffic_percentage: 80, volume_share_pct: 75, priority: 1,
      preferred_amount_min: 100, preferred_amount_max: 600, requests_per_minute_limit: 10,
      daily_turnover_min: 2000, daily_turnover_max: 9000)
    @beta = provider("beta", traffic_percentage: 20, volume_share_pct: 25, priority: 2, conversion_24h: 0.95,
      provider_margin_pct: 0.5)
    @state = state_for([ @alpha, @beta ])
  end

  test "projected count share favors provider behind target" do
    @state.record_selected("beta", 500)
    alpha = policy("count_share").call(provider: @alpha, operation:, state: @state, context: {})
    beta = policy("count_share").call(provider: @beta, operation:, state: @state, context: {})
    assert_operator alpha.normalized, :>, beta.normalized
    assert_equal 50.0, alpha.raw["projected_pct"]
  end

  test "projected volume share uses current amount" do
    @state.record_selected("beta", 1500)
    score = policy("volume_share").call(provider: @alpha, operation: operation(amount: 500), state: @state, context: {})
    assert_equal 25.0, score.raw["projected_pct"]
    assert_in_delta 0.5, score.normalized
  end

  test "optional volume and preferred range are disabled when absent" do
    plain = @beta.except("volume_share_pct", "preferred_amount_min", "preferred_amount_max")
    assert_nil policy("volume_share").call(provider: plain, operation:, state: @state, context: {})
    assert_nil policy("preferred_amount").call(provider: plain, operation:, state: @state, context: {})
  end

  test "cascade prioritizes lower priority" do
    context = { providers: [ @alpha, @beta ] }
    assert_operator policy("cascade").call(provider: @alpha, operation:, state: @state, context:).normalized, :>,
      policy("cascade").call(provider: @beta, operation:, state: @state, context:).normalized
  end

  test "preferred amount scores inside range" do
    assert_equal 1.0, policy("preferred_amount").call(provider: @alpha, operation:, state: @state, context: {}).normalized
    assert_operator policy("preferred_amount").call(provider: @alpha, operation: operation(amount: 1000), state: @state, context: {}).normalized, :<, 1
  end

  test "conversion and economy reward stronger values" do
    assert_operator policy("conversion").call(provider: @beta, operation:, state: @state, context: {}).normalized, :>,
      policy("conversion").call(provider: @alpha, operation:, state: @state, context: {}).normalized
    assert_operator policy("economy").call(provider: @beta, operation:, state: @state, context: {}).normalized, :>,
      policy("economy").call(provider: @alpha, operation:, state: @state, context: {}).normalized
  end

  test "load safe decreases before hard limit" do
    loaded = @alpha.merge("in_progress_count" => 2)
    loaded_state = state_for([ loaded, @beta ])
    assert_operator policy("load_safe").call(provider: loaded, operation:, state: loaded_state, context: {}).normalized, :<,
      policy("load_safe").call(provider: @alpha, operation:, state: @state, context: {}).normalized
  end

  test "intensity uses projected RPM" do
    score = policy("intensity").call(provider: @alpha, operation:, state: @state, context: {})
    assert_equal 1, score.raw["projected_rpm"]
    assert_in_delta 0.9, score.normalized
  end

  test "turnover commitment boosts unmet minimum and penalizes max" do
    score = policy("turnover_commitment").call(provider: @alpha, operation:, state: @state, context: {})
    assert_operator score.normalized, :>, 0.65
    over = @alpha.merge("daily_approved_amount" => 9000)
    assert_equal 0, policy("turnover_commitment").call(provider: over, operation:, state: state_for([ over ]), context: {}).normalized
  end

  test "combined weights choose weighted winner" do
    ranking = DuoRoute::Scorer.new(weights: { "conversion" => 10, "count_share" => 0.1 })
      .rank(providers: [ @alpha, @beta ], operation:, state: @state)
    assert_equal "beta", ranking.first["provider"]
    assert_equal %w[raw_value normalized_value weight contribution explanation], ranking.first["score_breakdown"]["conversion"].keys
  end

  test "tie break is deterministic by priority then name" do
    first = provider("zeta", priority: 2, conversion_24h: 0.8, traffic_percentage: 50)
    second = provider("alpha", priority: 1, conversion_24h: 0.8, traffic_percentage: 50)
    ranking = DuoRoute::Scorer.new(weights: { "conversion" => 1 }).rank(providers: [ first, second ], operation:, state: state_for([ first, second ]))
    assert_equal "alpha", ranking.first["provider"]
    second["priority"] = 2
    ranking = DuoRoute::Scorer.new(weights: { "conversion" => 1 }).rank(providers: [ first, second ], operation:, state: state_for([ first, second ]))
    assert_equal "alpha", ranking.first["provider"]
  end

  private

  def policy(name) = DuoRoute::Policies::Registry.new.build([ name ]).first
end
