# frozen_string_literal: true

require "test_helper"

class BackendAuditTest < ActiveSupport::TestCase
  test "decimal amounts preserve exact boundaries and cumulative totals" do
    external = provider(limit_amount_min: 0, limit_amount_max: nil, daily_amount_limit: 100,
      daily_approved_amount: 0, in_progress_amount_limit: nil)
    store = state_for([ external ])
    now = Time.iso8601(operation["created_at"])
    1000.times { store.reserve("alpha", 0.1, now); store.commit("alpha", 0.1) }
    assert_equal BigDecimal("100"), store.for("alpha")["daily_approved_amount"]
    external["daily_approved_amount"] = 0.1
    external["daily_amount_limit"] = 0.3
    registry = DuoRoute::Constraints::Registry.new
    assert registry.evaluate(provider: external, operation: operation(amount: 0.2), state: state_for([ external ]))["eligible"]
    assert_not registry.evaluate(provider: external, operation: operation(amount: 0.200001), state: state_for([ external ]))["eligible"]
    [ 1, 0.1, 0.001, 10**40 ].each do |amount|
      result = route(providers_data([ external.merge("daily_amount_limit" => nil, "daily_approved_amount" => 0) ]), [ operation(amount:) ])
      assert_equal amount, result.report["total_amount"]
      assert_kind_of Numeric, JSON.parse(DuoRoute.pretty_json(result.report))["total_amount"]
    end
  end

  test "lossy decimal JSON is rejected with field path instead of silent rounding" do
    error = assert_raises(DuoRoute::InputError) do
      DuoRoute::Input::Loader.json_string('{"amount":10000000000000000000000000000000000000000.1}')
    end
    assert_equal "unsupported_precision", error.issues.first.code
    assert_equal "input.amount", error.issues.first.path
    assert_raises(DuoRoute::Error) { DuoRoute::Money.number(BigDecimal("10000000000000000000000000000000000000000.1")) }
  end

  test "reservation ownership prevents duplicate commit and preserves inherited load" do
    store = state_for([ provider(in_progress_count: 2, in_progress_amount: 1000) ])
    store.rollback("alpha", 500)
    assert_equal 1000, store.for("alpha")["in_progress_amount"]
    assert_equal 2, store.for("alpha")["in_progress_count"]
    assert_raises(DuoRoute::Error) { store.commit("alpha", 500) }
    store.reserve("alpha", 500, Time.iso8601(operation["created_at"]))
    store.commit("alpha", 500)
    assert_raises(DuoRoute::Error) { store.commit("alpha", 500) }
    assert_equal 1500, store.for("alpha")["daily_approved_amount"]
  end

  test "table driven below at above every numeric hard boundary" do
    cases = [
      [ "limit_amount_min", [ 499.99, 500, 500.01 ], [ true, true, false ] ],
      [ "limit_amount_max", [ 499.99, 500, 500.01 ], [ false, true, true ] ],
      [ "daily_amount_limit", [ 1499.99, 1500, 1500.01 ], [ false, true, true ] ],
      [ "in_progress_count_limit", [ 0, 1, 2 ], [ false, true, true ] ],
      [ "in_progress_amount_limit", [ 499.99, 500, 500.01 ], [ false, true, true ] ],
      [ "requests_per_minute_limit", [ 0, 1, 2 ], [ false, true, true ] ],
      [ "provider_margin_pct", [ 1.49, 1.5, 1.51 ], [ true, true, false ] ],
      [ "available_requisites", [ 0, 1, 2 ], [ false, true, true ] ]
    ]
    cases.each do |field, values, expected|
      values.zip(expected).each do |value, allowed|
        item = provider.merge(field => value)
        evaluation = DuoRoute::Constraints::Registry.new.evaluate(provider: item, operation:, state: state_for([ item ]))
        assert_equal allowed, evaluation["eligible"], "#{field}=#{value}"
      end
    end
  end

  test "mandatory fields reject null blanks types nonfinite and invalid dates with paths" do
    changes = { "operation_id" => [ nil, "", " ", 1 ], "bank" => [ nil, "", "  ", [] ],
      "amount" => [ nil, 0, -0.1, "500", Float::NAN, Float::INFINITY ],
      "created_at" => [ nil, "", "yesterday", "abcT12:00:00Z", "2026-02-30T10:00:00Z", "2026-07-30T25:00:00Z", "2026-07-30T10:00:00" ] }
    changes.each do |field, values|
      values.each do |value|
        issues = validate(operations: [ operation.merge(field => value) ])
        assert issues.any? { |issue| issue.path == "$operations[0].#{field}" }, "#{field}=#{value.inspect}"
      end
    end
    [ nil, "", 7 ].each do |value|
      %w[payment_system status].each do |field|
        issues = validate(data: providers_data([ provider.merge(field => value) ]))
        assert issues.any? { |issue| issue.path == "$.providers[0].#{field}" }
      end
    end
    %w[daily_approved_amount in_progress_count in_progress_amount available_requisites provider_margin_pct merchant_margin_pct].each do |field|
      assert validate(data: providers_data([ provider.merge(field => nil) ])).any? { |issue| issue.path == "$.providers[0].#{field}" }
    end
    %w[exclude_banks allow_negative_agreement].each do |field|
      assert validate(data: providers_data([ provider.merge(field => "false") ])).any? { |issue| issue.path.end_with?(field) }
    end
    %w[in_progress_count requests_per_minute_limit available_requisites].each do |field|
      assert validate(data: providers_data([ provider.merge(field => 1.5) ])).any? { |issue| issue.code == "integer_required" }
    end
  end

  test "JSON YAML CSV empty malformed encoding size and structural errors" do
    loader = DuoRoute::Input::Loader
    %i[json_string config_string csv_string].each do |method|
      [ "", "  \n", "\xff".b ].each { |text| assert_raises(DuoRoute::InputError) { loader.public_send(method, text) } }
    end
    headers = "operation_id,created_at,amount,bank,payment_system,status,latency_sec"
    assert_empty loader.csv_string(headers + "\n")
    [ headers + ",amount\n", headers + "\nx,y\n", headers + "\nx,y,1,a,p,approved,1,extra\n", "a,b\n1,2\n" ].each do |text|
      assert_raises(DuoRoute::InputError) { loader.csv_string(text) }
    end
    large = "x" * (loader::MAX_BYTES + 1)
    assert_raises(DuoRoute::InputError) { loader.json_string(large) }
    assert_raises(DuoRoute::InputError) { loader.json_string("{") }
    assert_raises(DuoRoute::InputError) { loader.config_string("x: [") }
    [ nil, [], "x", 5 ].each { |data| assert validate(data:).any? }
    [ nil, {}, "x", 5, [] ].each { |operations| assert validate(operations:).any? }
    assert_empty validate(operations: [ operation.merge("new_optional_field" => "preserved") ])
  end

  test "provider edge cases are rejected or safely excluded without silent correction" do
    [ [], [ provider ], [ provider("spacepayments"), provider("spacepayments") ] ].each do |items|
      assert validate(data: providers_data.merge("providers" => items)).any?
    end
    assert_empty validate(data: providers_data([]))
    assert validate(data: providers_data([], fallback: provider("spacepayments", available_requisites: Float::NAN))).any?
    [ "limit_amount_min", "daily_amount_limit", "in_progress_amount_limit", "traffic_percentage" ].each do |field|
      assert validate(data: providers_data([ provider.merge(field => -1) ])).any?
    end
    assert validate(data: providers_data([ provider(traffic_percentage: 101) ])).any?
    assert validate(data: providers_data([ provider(traffic_percentage: 80) ])).any?
    assert validate(data: providers_data([ provider(limit_amount_min: 1001) ])).any?
    overloaded = provider(daily_approved_amount: 20_000, in_progress_count: 9, in_progress_amount: 4000)
    result = route(providers_data([ overloaded ]))
    assert_equal "spacepayments", result.decisions.first["selected_provider"]
    assert_equal 20_000, result.decisions.first.dig("state_after", "alpha", "daily_approved_amount")
    assert_raises(DuoRoute::InputError) { DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, settings: [ "provider_overrides.missing.priority=1" ]).call }
    assert_raises(DuoRoute::InputError) { DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, settings: [ "routing.fallback_provider=missing" ]).call }
  end

  test "UTC days reset daily only and reject operations before snapshot" do
    data = providers_data([ provider(daily_approved_amount: 9500) ])
    ops = [ operation("a", created_at: "2026-07-30T23:59:59Z"), operation("b", created_at: "2026-07-31T03:00:00+03:00"), operation("c", created_at: "2026-08-02T00:00:00Z") ]
    result = route(data, ops)
    assert_equal [ 10_000, 500, 500 ], result.decisions.map { |row| row.dig("state_after", "alpha", "daily_approved_amount") }
    assert_equal %w[2026-07-30 2026-07-31 2026-08-02], result.report["daily_state_history"].keys
    assert_includes validate(operations: [ operation(created_at: "2026-07-30T05:59:59Z") ]).map(&:code), "before_snapshot"
  end

  test "RPM left endpoint open right endpoint closed and rejected calls persist" do
    now = Time.iso8601(operation["created_at"])
    [ -59.999, -60, -60.001 ].zip([ 1, 0, 0 ]).each do |offset, count|
      store = state_for([ provider ])
      store.reserve("alpha", 0.1, now + offset)
      store.rollback("alpha", 0.1)
      assert_equal count, store.rpm("alpha", now)
    end
    data = providers_data([ provider(requests_per_minute_limit: 1) ])
    result = route(data, [ operation("a"), operation("b") ], outcomes: { "outcomes" => { "a:alpha" => "rejected" }, "default" => "approved" })
    assert_equal "rate_limit_exceeded", result.decisions.last["attempts"].find { |row| row["provider"] == "alpha" }["reason"]
  end

  test "all cascade result combinations preserve reserves attempts and total latency" do
    data = providers_data([ provider("alpha", traffic_percentage: 50), provider("beta", traffic_percentage: 50, priority: 2) ])
    %w[approved rejected expired].repeated_permutation(3) do |results|
      %w[fallback_on_timeout hold_until_status].each do |mode|
        [ nil, "approved", "rejected" ].each do |late|
          outcomes = { "outcomes" => %w[alpha beta spacepayments].zip(results).to_h { |name, status| [ "op_1:#{name}", { "result" => status, "latency_sec" => 0.25, "status_check_result" => late } ] } }
          result = route(data, outcomes:, mode:)
          decision = result.decisions.first
          called = decision["attempts"].select { |attempt| attempt.key?("result") }
          assert_equal called.length * 0.25, decision["latency_sec"]
          assert_equal called.map { |row| row["provider"] }.uniq.size, called.size
          called.each do |attempt|
            pending = attempt["result"] == "expired" && mode == "hold_until_status" && late.nil?
            assert_equal pending ? 1 : 0, decision.dig("state_after", attempt["provider"], "in_progress_count")
          end
        end
      end
    end
  end

  test "future history is excluded before simulation and calibration" do
    rows = 20.times.map { |i| history_row(i) }
    future = history_row(99).merge("created_at" => "2026-07-30T09:00:00+03:00", "latency_sec" => "1", "status" => "rejected")
    configuration = config.merge("simulation" => { "source" => "history", "minimum_samples" => 20 }, "calibration" => { "enabled" => true, "minimum_samples" => 20, "prior_strength" => 30 })
    runner = DuoRoute::Runner.new(providers_data:, operations: [ operation ], config: configuration, history: rows + [ future ])
    result = runner.call
    assert_equal 1, result.manifest["excluded_future_history_rows"]
    assert_equal 20, result.manifest.dig("simulation", "alpha", "history_records")
    assert_equal 1, result.manifest.dig("simulation", "alpha", "approved_rate")
    assert_in_delta 0.88, runner.providers_data["providers"].first["effective_conversion"]
    [ [], rows.first(19) ].each do |history|
      result = DuoRoute::Runner.new(providers_data:, operations: [ operation ], config: configuration, history:).call
      assert result.manifest.dig("simulation", "alpha", "provider_snapshot_fallback")
    end
  end

  test "history errors have field or row paths and pure status samples work" do
    [ history_row(1).merge("status" => "unknown"), history_row(1).merge("latency_sec" => "-1"), history_row(1).merge("payment_system" => "unknown") ].each do |row|
      assert validate(history: [ row ]).any? { |issue| issue.path.start_with?("$history[") }
    end
    assert_includes validate(history: [ history_row(1), history_row(1) ]).map(&:code), "duplicate_history_row"
    %w[approved rejected expired].each do |status|
      rows = 20.times.map { |i| history_row(i).merge("status" => status) }
      profile = DuoRoute::Simulation::Profile.new(providers: [ provider ], history: rows, config: {}, seed: 42).profiles["alpha"]
      assert_equal 1, profile["#{status}_rate"]
    end
  end

  test "zero weight cannot influence ranking or conflict evidence" do
    a = provider("alpha", priority: 1, conversion_24h: 0.2, traffic_percentage: 50)
    b = provider("beta", priority: 2, conversion_24h: 0.99, traffic_percentage: 50)
    rank = DuoRoute::Scorer.new(weights: { "count_share" => 1, "conversion" => 0 }, policy_priorities: %w[conversion count_share]).rank(providers: [ a, b ], operation:, state: state_for([ a, b ]))
    assert_equal "alpha", rank.first["provider"]
    assert_not rank.first["score_breakdown"].key?("conversion")
    assert validate(configuration: config({ "conversion" => 0 })).any? { |issue| issue.code == "zero_weights" }
  end

  test "inputs remain unchanged and repeated runner calls agree" do
    data, ops, configuration, history = providers_data, [ operation ], config, [ history_row(1) ]
    original = JSON.generate([ data, ops, configuration, history ])
    runner = DuoRoute::Runner.new(providers_data: data, operations: ops, config: configuration, history:)
    first = runner.call
    assert_equal first.decisions, runner.call.decisions
    assert_equal original, JSON.generate([ data, ops, configuration, history ])
  end

  test "strict output detects corrupted latency selection eligibility reason and report amounts" do
    result = route
    validator = DuoRoute::Reporting::OutputValidator.new
    [ ->(row) { row["latency_sec"] = Float::INFINITY }, ->(row) { row["attempts"] << row["attempts"].first.dup },
      ->(row) { row["constraint_matrix"]["alpha"]["eligible"] = false }, ->(row) { row["attempts"].first["reason"] = "invented" } ].each do |mutation|
      decisions = JSON.parse(JSON.generate(result.decisions))
      mutation.call(decisions.first)
      assert validator.decisions(decisions).any?
    end
    result.report["distribution"]["alpha"]["share_pct"] = 999
    assert validator.consistency(result, operations: [ operation ], providers: providers_data["providers"]).any? { |issue| issue.code == "percentage_mismatch" }
    result.report["total_amount"] += 1
    assert validator.consistency(result, operations: [ operation ], providers: providers_data["providers"]).any?
  end

  private

  def history_row(i)
    { "operation_id" => "h#{i}", "created_at" => "2026-07-29T09:00:00+03:00", "amount" => "0.1", "bank" => "sberbank", "payment_system" => "alpha", "status" => "approved", "latency_sec" => "1" }
  end

  def validate(data: providers_data, operations: [ operation ], configuration: config, history: [])
    DuoRoute::Validation::InputValidator.new.call(providers_data: data, operations:, config: configuration, history:)
  end

  def route(data = providers_data, operations = [ operation ], outcomes: { "default" => "approved" }, mode: "fallback_on_timeout")
    DuoRoute::Runner.new(providers_data: data, operations:, config: config({ "cascade" => 1 }, timeout: mode), outcomes:).call
  end
end
