# frozen_string_literal: true

require "test_helper"

class ConstraintsTest < ActiveSupport::TestCase
  def setup
    @operation = operation
  end

  test "amount boundaries are inclusive" do
    item = provider(limit_amount_min: 500, limit_amount_max: 500)
    assert evaluation(item)["eligible"]
  end

  test "minimum and maximum have stable codes" do
    assert_equal "amount_below_minimum", first_failure(provider(limit_amount_min: 501))
    assert_equal "amount_exceeds_limit", first_failure(provider(limit_amount_max: 499))
  end

  test "inactive provider is rejected" do
    assert_equal "provider_inactive", first_failure(provider(status: "paused"))
  end

  test "daily amount exact limit passes and one over fails" do
    assert evaluation(provider(daily_approved_amount: 9500))["eligible"]
    assert_includes failure_codes(provider(daily_approved_amount: 9501)), "daily_amount_limit_exceeded"
  end

  test "in progress count exact limit passes and one over fails" do
    assert evaluation(provider(in_progress_count: 2))["eligible"]
    assert_includes failure_codes(provider(in_progress_count: 3)), "in_progress_count_limit_exceeded"
  end

  test "in progress amount exact limit passes and one over fails" do
    assert evaluation(provider(in_progress_amount: 2500))["eligible"]
    assert_includes failure_codes(provider(in_progress_amount: 2501)), "in_progress_amount_limit_exceeded"
  end

  test "empty banks permits known and unknown banks" do
    assert evaluation(provider(banks: []))["eligible"]
    assert evaluation(provider(banks: []), operation(bank: "unknown"))["eligible"]
  end

  test "include and exclude bank semantics" do
    assert_includes failure_codes(provider(banks: [ "vtb" ])), "bank_not_in_list"
    assert_includes failure_codes(provider(banks: [ "sberbank" ], exclude_banks: true)), "bank_excluded"
    assert evaluation(provider(banks: [ "vtb" ], exclude_banks: true))["eligible"]
  end

  test "negative margin agreement" do
    assert_includes failure_codes(provider(provider_margin_pct: 2.0)), "negative_margin_not_allowed"
    assert evaluation(provider(provider_margin_pct: 2.0, allow_negative_agreement: true))["eligible"]
  end

  test "requisites are required" do
    assert_includes failure_codes(provider(available_requisites: 0)), "no_available_requisites"
  end

  test "nil numeric limits are unlimited" do
    item = provider(limit_amount_min: nil, limit_amount_max: nil, daily_amount_limit: nil,
      in_progress_count_limit: nil, in_progress_amount_limit: nil)
    assert evaluation(item, operation(amount: 10_000_000))["eligible"]
  end

  test "sliding RPM counts actual attempts and expires old timestamps" do
    item = provider(requests_per_minute_limit: 1)
    state = state_for([ item ])
    now = Time.iso8601(@operation["created_at"])
    state.reserve("alpha", 500, now)
    assert_includes registry.evaluate(provider: item, operation: @operation, state:)["failures"].map { |f| f["code"] }, "rate_limit_exceeded"
    later = operation(created_at: (now + 61).iso8601)
    assert registry.evaluate(provider: item, operation: later, state:)["eligible"]
  end

  test "audit contains every check not only first failure" do
    result = evaluation(provider(status: "paused", available_requisites: 0))
    assert_equal 10, result["checks"].length
    assert_equal %w[provider_inactive no_available_requisites], result["failures"].map { |failure| failure["code"] }.intersection(%w[provider_inactive no_available_requisites])
  end

  private

  def registry = DuoRoute::Constraints::Registry.new
  def evaluation(item, op = @operation) = registry.evaluate(provider: item, operation: op, state: state_for([ item ]))
  def failure_codes(item) = evaluation(item)["failures"].map { |failure| failure["code"] }
  def first_failure(item) = failure_codes(item).first
end
