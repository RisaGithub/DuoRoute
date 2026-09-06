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

  test "evaluation decision and actual defaults agree across config CLI and Web" do
    report = DuoRoute::Input::Loader.json_file(Rails.root.join("artifacts/verification/DEFAULT_STRATEGY_FINAL_EVALUATION.json"))
    selection = DuoRoute::DefaultSelection.record
    assert_equal "complete", report["status"]
    assert_equal report.dig("decision", "implemented_default"), selection["strategy"]
    assert_equal report.dig("decision", "default_version"), selection["version"]
    %w[default final].each do |name|
      settings = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/#{name}.yml"))
      assert_equal selection["strategy"], settings.dig("routing", "default_strategy")
      resolved = DuoRoute::Configuration.resolve(settings, strategy: selection["strategy"])
      assert_equal selection["weights"], resolved.dig("presets", selection["strategy"], "weights")
      assert_equal false, settings.dig("calibration", "enabled")
    end
    assert_equal [ 223, 227 ], report.dig("methodology", "splits", "validation")
    assert_equal [ 331, 347 ], report.dig("methodology", "splits", "holdout")
    options, = DuoRoute::CLI::App.new([], out: StringIO.new, err: StringIO.new).send(:common_options)
    assert_equal selection["strategy"], options[:preset]
  end
end
