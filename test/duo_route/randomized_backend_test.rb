# frozen_string_literal: true

require "test_helper"

class RandomizedBackendTest < ActiveSupport::TestCase
  test "fixed seeds and every strategy preserve eligibility online prefix and report invariants" do
    [ 42, 17, 101 ].each do |seed|
      random = Random.new(seed)
      bundle = DuoRoute::Generators::Scenario.new(name: "normal", operations: 80, providers: 5, seed:).call
      bundle["providers"]["providers"][0...-1].each do |provider|
        provider["banks"] = random.rand(2).zero? ? [] : %w[sberbank alfa]
        provider["exclude_banks"] = random.rand(2).zero?
        provider["requests_per_minute_limit"] = random.rand(1..10)
        provider["in_progress_count"] = random.rand(0..10)
      end
      bundle["operations"].each_with_index do |operation, index|
        operation["amount"] = [ 500, 500.01, 30_000, 200_001 ].sample(random:)
        operation["created_at"] = (Time.iso8601(bundle["providers"]["snapshot_at"]) + index / 3).iso8601
      end
      (DuoRoute::StrategyCatalog.all.keys + [ "balanced" ]).each do |strategy|
        configuration = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml"))
        run = ->(operations) { DuoRoute::Runner.new(providers_data: bundle["providers"], operations:, config: configuration, preset: strategy, seed:).call }
        result = run.call(bundle["operations"])
        prefix = run.call(bundle["operations"].first(20))
        assert_equal prefix.decisions, result.decisions.first(20), "online prefix: #{strategy}/#{seed}"
        assert_equal result.decisions, run.call(bundle["operations"]).decisions
        providers = bundle["providers"]["providers"].to_h { |provider| [ provider["payment_system"], provider ] }
        result.decisions.zip(bundle["operations"]).each do |decision, operation|
          called = decision["attempts"].select { |attempt| attempt.key?("result") }
          assert_equal called.map { |row| row["provider"] }.uniq.length, called.length
          assert_equal called.sum { |row| row["latency_sec"] }, decision["latency_sec"]
          called.each do |attempt|
            provider = providers.fetch(attempt["provider"])
            before = decision["state_before"].fetch(attempt["provider"])
            assert_equal "active", provider["status"]
            assert_operator provider["available_requisites"], :>, 0
            assert_operator operation["amount"], :>=, provider["limit_amount_min"] if provider["limit_amount_min"]
            assert_operator operation["amount"], :<=, provider["limit_amount_max"] if provider["limit_amount_max"]
            assert_operator before["requests_last_minute"] + 1, :<=, provider["requests_per_minute_limit"] if provider["requests_per_minute_limit"]
            if provider["banks"].any?
              assert_equal !provider["exclude_banks"], provider["banks"].include?(operation["bank"])
            end
          end
          if decision["fallback_used"]
            assert_empty decision["eligible_pool"] - called.map { |attempt| attempt["provider"] }
          end
        end
      end
    end
  end

  test "evaluation selected weights equal web CLI and final defaults" do
    report = DuoRoute::Input::Loader.json_file(Rails.root.join("artifacts/verification/default_strategy_evaluation.json"))
    %w[default final].each do |name|
      settings = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/#{name}.yml"))
      assert_equal report["selected_weights"], settings.dig("presets", "balanced", "weights")
      assert_equal report["selected_calibration"], settings.dig("calibration", "enabled")
    end
    assert_equal [ 42, 17 ], report["seeds"]
    assert_equal [ 101, 309 ], report["holdout_seeds"]
  end
end
