# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  test "catalog contains exactly seven specification strategies and defaults" do
    catalog = DuoRoute::StrategyCatalog.all
    assert_equal %w[count_share volume_share cascade amount_range conversion intensity turnover_commitment], catalog.keys
    assert_equal DuoRoute::Input::Loader.config_file(DuoRoute::StrategyCatalog::PATH), catalog
    assert_equal 40, catalog.dig("count_share", "parameters", "provider_overrides", "vipay", "traffic_percentage")
    assert_equal 50, catalog.dig("volume_share", "parameters", "provider_overrides", "vipay", "volume_share_pct")
    assert_equal 2_000_000, catalog.dig("turnover_commitment", "parameters", "provider_overrides", "payflow", "daily_turnover_min")
  end

  test "resolver applies strategy defaults then user overrides and snapshots them" do
    resolved = DuoRoute::Configuration.resolve(config, strategy: "volume_share", settings: [ "provider_overrides.vipay.volume_share_pct=60" ])
    assert_equal 60, resolved.dig("provider_overrides", "vipay", "volume_share_pct")
    assert_nil resolved.dig("provider_overrides", "payflow", "volume_share_pct")
    assert_equal resolved, DuoRoute::Configuration.resolve(resolved, strategy: "volume_share")
    assert_empty config["provider_overrides"]
  end

  test "combined and custom factors retain economy and load policies" do
    resolved = DuoRoute::Configuration.resolve(config, strategy: "custom", settings: [ 'presets.custom.weights={"load_safe":2,"economy":1}', 'presets.custom.policy_priorities=["economy","load_safe"]' ])
    assert_equal({ "load_safe" => 2, "economy" => 1 }, resolved.dig("presets", "custom", "weights"))
    DuoRoute::Runner.new(providers_data:, operations: [ operation ], config: resolved, preset: "custom").validate!
  end

  test "unknown settings types ranges and priorities are rejected" do
    [ "simulation.typo=1", "routing.timeout_mode=no", "provider_overrides.alpha.conversion_24h=2", "presets.balanced.weights.load_safe=-1", 'presets.balanced.policy_priorities=["typo"]', "simulation.minimum_samples=0", "simulation.failure_expired_share=2", "simulation.providers=[]", "routing=oops", "routing.fallback_provider=null", "calibration.prior_strength=null", "calibration.minimum_samples=0.5" ].each do |setting|
      assert_raises(DuoRoute::InputError, setting) do
        DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, settings: [ setting ]).validate!
      end
    end
  end

  test "history profiles calculate all results and latency with explicit sample threshold" do
    rows = %w[approved approved rejected expired].each_with_index.map { |status, index| { "payment_system" => "alpha", "status" => status, "latency_sec" => (index + 1) * 10 } }
    profile = DuoRoute::Simulation::Profile.new(providers: [ provider ], history: rows, config: { "source" => "history", "minimum_samples" => 4 }, seed: 42).profiles["alpha"]
    assert_equal [ 0.5, 0.25, 0.25, 25.0 ], profile.values_at("approved_rate", "rejected_rate", "expired_rate", "average_latency_sec")
    assert_equal 4, profile["history_records"]
    assert_not profile["provider_snapshot_fallback"]
    fallback = DuoRoute::Simulation::Profile.new(providers: [ provider ], history: rows, config: { "minimum_samples" => 5, "failure_expired_share" => 0.25 }, seed: 42).profiles["alpha"]
    assert_equal 0.8, fallback["approved_rate"]
    assert_in_delta 0.05, fallback["expired_rate"]
    assert_equal 20, fallback["average_latency_sec"]
    assert fallback["provider_snapshot_fallback"]
  end

  test "custom probabilities sum to one and approval-only split is explicit" do
    simulation = { "source" => "custom", "failure_expired_share" => 0.5, "providers" => { "alpha" => { "approved_rate" => 0.6 } } }
    profile = DuoRoute::Simulation::Profile.new(providers: [ provider ], history: [], config: simulation, seed: 7).profiles["alpha"]
    assert_in_delta 0.2, profile["rejected_rate"]
    assert_in_delta 0.2, profile["expired_rate"]
    simulation["providers"]["alpha"].merge!("rejected_rate" => 0.3, "expired_rate" => 0.3)
    assert_raises(DuoRoute::InputError) { DuoRoute::Simulation::Profile.new(providers: [ provider ], history: [], config: simulation, seed: 7) }
  end

  test "runner decisions and simulation evidence are deterministic" do
    run = -> { DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, seed: 78).call }
    first, second = run.call, run.call
    assert_equal first.decisions, second.decisions
    assert_equal 78, first.decisions.first.dig("simulation", "seed")
    assert_equal first.manifest["simulation"], first.report["simulation"]
  end

  test "strategy and preset CLI aliases produce identical decisions and resolved config" do
    Dir.mktmpdir do |dir|
      results = %w[--strategy --preset].map.with_index do |flag, index|
        decisions = File.join(dir, "d#{index}.json")
        report = File.join(dir, "r#{index}.json")
        args = [ "route", flag, "count_share", "--simulation-source", "provider_snapshot", "--seed", "123", "--set", "provider_overrides.vipay.traffic_percentage=40", "--quiet", "--decisions", decisions, "--report", report ]
        assert_equal 0, DuoRoute::CLI::App.new(args, out: StringIO.new, err: StringIO.new).run
        [ JSON.parse(File.read(decisions)), JSON.parse(File.read("#{report}.config.json")) ]
      end
      assert_equal results.first, results.last
    end
  end

  test "invalid CLI settings do not write any artifacts" do
    Dir.mktmpdir do |dir|
      assert_equal 2, DuoRoute::CLI::App.new([ "route", "--set", "simulation.unknown=10", "--decisions", "#{dir}/d.json", "--report", "#{dir}/r.json" ], out: StringIO.new, err: StringIO.new).run
      assert_empty Dir.children(dir)
    end
  end
  test "scripted validation follows reachable paths and rejects missing responses before writing" do
    runner = DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, outcomes: { "outcomes" => { "op_1:alpha" => "approved" } })
    assert runner.validate!
    assert_raises(DuoRoute::InputError) do
      DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, outcomes: { "outcomes" => {} }).validate!
    end
  end

  test "history latency median and CLI set seed are configurable" do
    rows = [ 1, 2, 90 ].map { |latency| { "payment_system" => "alpha", "status" => "approved", "latency_sec" => latency } }
    profile = DuoRoute::Simulation::Profile.new(providers: [ provider ], history: rows, config: { "minimum_samples" => 3, "latency_method" => "median" }, seed: 1).profiles["alpha"]
    assert_equal 2, profile["average_latency_sec"]
    result = DuoRoute::Runner.new(providers_data:, operations: [ operation ], config:, settings: [ "seed=765" ]).call
    assert_equal 765, result.manifest["seed"]
  end
end
