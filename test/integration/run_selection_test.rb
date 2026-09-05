# frozen_string_literal: true

require "test_helper"

class RunSelectionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    RoutingRun.delete_all
  end

  def saved_run(name, provider_name, completed_at)
    RoutingRun.create!(name:, status: "completed", preset: "balanced", timeout_mode: "fallback_on_timeout", simulator_mode: "seeded", seed: 42,
      providers_json: { "providers" => [ { "payment_system" => provider_name, "status" => "active", "banks" => [] } ] }.to_json,
      operations_json: "[]", config_json: "{}", report_json: { "total_operations" => 0, "total_amount" => 0 }.to_json, completed_at:)
  end

  test "latest completed run and explicit run_id isolate dashboard and provider snapshots" do
    old = saved_run("Older run", "only_old", 2.days.ago)
    latest = saved_run("Newer run", "only_new", 1.day.ago)
    [ root_path, providers_path ].each do |path|
      get path
      assert_response :success
      assert_select ".provider-card", /only_new/
      assert_select ".provider-card", text: /only_old/, count: 0
      get path, params: { run_id: old.id }
      assert_response :success
      assert_select ".provider-card", /only_old/
      assert_select ".provider-card", text: /only_new/, count: 0
      assert_select "a[href='#{provider_path('only_old', run_id: old.id)}']"
    end
    get provider_path("only_old", run_id: old.id)
    assert_response :success
    get provider_path("only_old", run_id: latest.id)
    assert_response :not_found
    get root_path, params: { run_id: 999999 }
    assert_response :not_found
  end

  test "deleted routes are absent and strategy cards are exactly seven" do
    routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_not routes.any? { |path| path.include?("analytics") || path.include?("methodology") }
    get strategies_path
    assert_response :success
    assert_select ".strategy-list article", count: 7
  end

  test "web config and core CLI configuration agree and stored run remains reproducible" do
    settings = "provider_overrides.vipay.volume_share_pct=60\nsimulation.minimum_samples=2"
    post runs_path, params: { name: "Shared configuration", preset: "volume_share", simulator_mode: "history", seed: 42, settings: }
    assert_response :redirect
    run = RoutingRun.find_by!(name: "Shared configuration")
    expected = DuoRoute::Configuration.resolve(DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s), strategy: "volume_share", settings: settings.lines.map(&:strip))
    assert_equal expected["provider_overrides"], run.config["provider_overrides"]
    assert_equal expected["simulation"], run.config["simulation"]
    perform_enqueued_jobs
    run.reload
    assert_equal "completed", run.status, run.error_message
    repeated = DuoRoute::Runner.new(providers_data: run.providers, operations: run.operations, config: run.config, preset: run.preset, seed: run.seed, history: DuoRoute::Input::Loader.csv_string(run.history_csv)).call
    assert_equal run.decisions, repeated.decisions
    Dir.mktmpdir do |dir|
      paths = { providers: run.providers_json, operations: run.operations_json, config: run.config_json }
      paths.each { |name, content| File.write("#{dir}/#{name}.json", content) }
      File.write("#{dir}/history.csv", run.history_csv)
      args = [ "route", "--history", "#{dir}/history.csv", "--providers", "#{dir}/providers.json", "--operations", "#{dir}/operations.json", "--config", "#{dir}/config.json", "--strategy", run.preset, "--seed", run.seed.to_s, "--quiet", "--decisions", "#{dir}/decisions.json", "--report", "#{dir}/report.json" ]
      assert_equal 0, DuoRoute::CLI::App.new(args, out: StringIO.new, err: StringIO.new).run
      assert_equal run.decisions, JSON.parse(File.read("#{dir}/decisions.json"))
    end
    assert_equal run.config, run.manifest["resolved_configuration"]
    assert run.config.dig("input_metadata", "providers", "sha256")
  end
end
