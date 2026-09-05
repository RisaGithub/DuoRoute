# frozen_string_literal: true

require "test_helper"

class InputValidationTest < ActiveSupport::TestCase
  test "valid input returns no issues" do
    assert_empty validator.call(providers_data:, operations: [ operation ], config: config)
  end

  test "aggregates duplicates timestamps amounts shares and fallback errors" do
    bad = providers_data
    bad["providers"].first["traffic_percentage"] = 80
    bad["providers"].last["status"] = "paused"
    operations = [ operation("same", amount: 0, created_at: "nope"), operation("same", amount: -1) ]
    codes = validator.call(providers_data: bad, operations:, config: config).map(&:code)
    %w[traffic_share_sum fallback_unavailable invalid_iso8601 amount_not_positive duplicate_operation_id].each { |code| assert_includes codes, code }
  end

  test "detects provider duplicates ranges and invalid numeric fields" do
    one = provider("dup", traffic_percentage: 50, conversion_24h: 1.2, limit_amount_min: 2000, limit_amount_max: 1000)
    two = provider("dup", traffic_percentage: 50)
    codes = validator.call(providers_data: providers_data([ one, two ]), operations: [ operation ], config: config).map(&:code)
    %w[duplicate_payment_system out_of_range invalid_amount_range].each { |code| assert_includes codes, code }
  end

  test "safe YAML refuses aliases and object construction" do
    assert_raises(DuoRoute::InputError) { DuoRoute::Input::Loader.config_string("a: &a [1]\nb: *a") }
    assert_raises(DuoRoute::InputError) { DuoRoute::Input::Loader.config_string("--- !ruby/object:Object {}") }
  end

  test "malformed JSON CSV and config report machine readable errors" do
    error = assert_raises(DuoRoute::InputError) { DuoRoute::Input::Loader.json_string("{") }
    assert_equal "malformed_json", error.issues.first.code
    error = assert_raises(DuoRoute::InputError) { DuoRoute::Input::Loader.csv_string("a,b\n\"x") }
    assert_equal "malformed_csv", error.issues.first.code
    bad_config = { "presets" => { "x" => { "weights" => { "mystery" => -1 } } }, "routing" => { "timeout_mode" => "magic" } }
    codes = validator.call(providers_data:, operations: [ operation ], config: bad_config).map(&:code)
    %w[unknown_timeout_mode unknown_policy invalid_weight zero_weights].each { |code| assert_includes codes, code }
  end

  test "empty queue is invalid" do
    assert_includes validator.call(providers_data:, operations: [], config: config).map(&:code), "empty_queue"
  end

  test "history validation includes line number" do
    issues = validator.call(providers_data:, operations: [ operation ], config: config,
      history: [ { "_line" => 7, "operation_id" => "h", "created_at" => "bad", "amount" => "x", "bank" => "a",
        "payment_system" => "alpha", "status" => "mystery", "latency_sec" => "x" } ])
    assert issues.all? { |issue| issue.path.include?("7") }
    assert_includes issues.map(&:code), "invalid_status"
  end

  private

  def validator = DuoRoute::Validation::InputValidator.new
end
