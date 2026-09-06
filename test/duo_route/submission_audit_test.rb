# frozen_string_literal: true

require "test_helper"
require_relative "../../script/audit_submission"

class SubmissionAuditTest < ActiveSupport::TestCase
  def fixture
    data = providers_data
    ops = [ operation, operation("second", created_at: "2026-07-31T09:05:00+03:00") ]
    result = DuoRoute::Runner.new(providers_data: data, operations: ops, config: config,
      outcomes: { "default" => { "result" => "approved", "latency_sec" => 2 } }).call
    { providers: data, operations: ops, decisions: result.decisions, report: result.report }
  end

  test "independent audit accepts full and shortened decisions and day rollover" do
    inputs = fixture
    assert SubmissionAudit.new(**inputs).call
    inputs[:decisions].each { |row| row.delete("state_before"); row.delete("state_after"); row.delete("constraint_matrix") }
    assert SubmissionAudit.new(**inputs).call
  end

  test "mutations in provider amount percentages latency ids attempts and report all fail" do
    mutations = {
      provider: ->(i) { i[:decisions][0]["selected_provider"] = "unknown" },
      amount: ->(i) { i[:operations][0]["amount"] += 1 },
      volume: ->(i) { i[:report]["volume_distribution"]["alpha"]["amount"] += 1 },
      percentage: ->(i) { i[:report]["distribution"]["alpha"]["share_pct"] -= 1 },
      latency: ->(i) { i[:decisions][0]["latency_sec"] = -1 },
      operation_id: ->(i) { i[:decisions][1]["operation_id"] = i[:decisions][0]["operation_id"] },
      attempts: ->(i) { i[:decisions][0]["attempts"] << i[:decisions][0]["attempts"].last.dup },
      selection: ->(i) { i[:decisions][0]["attempts"].first["decision"] = "skipped" },
      sequence: ->(i) { i[:decisions][0]["attempts"].first["sequence"] = 2 },
      result: ->(i) { i[:decisions][0]["simulated_result"] = "unknown" },
      performance: ->(i) { i[:report]["provider_performance"]["alpha"]["success_rate_pct"] -= 1 },
      utilization: ->(i) { i[:report]["capacity_utilization"]["alpha"]["daily_utilization_pct"] += 1 },
      period: ->(i) { i[:report]["period"] = "wrong" },
      report: ->(i) { i[:report]["total_operations"] += 1 },
      state: ->(i) { i[:decisions][0]["state_after"]["alpha"]["daily_approved_amount"] += 1 },
      secret: ->(i) { i[:report]["api_key"] = "DO_NOT_PRINT" },
      infinity: ->(i) { i[:report]["average_latency_sec"] = Float::INFINITY }
    }
    mutations.each do |name, mutate|
      input = fixture
      mutate.call(input)
      assert_raises(SubmissionAudit::Invalid, name.to_s) { SubmissionAudit.new(**input).call }
    end
  end

  test "audit rejects a forged eligible matrix and replays hard limits independently" do
    input = fixture
    # Remove checks and output states, then forge a consistent report digest after changing the input limit.
    input[:providers]["providers"][0]["limit_amount_max"] = 100
    audit = SubmissionAudit.new(**input)
    input[:report]["reproducibility"]["providers_sha256"] = audit.send(:digest, input[:providers])
    input[:decisions].each { |d| d.delete("constraint_matrix"); d.delete("state_before"); d.delete("state_after"); d.delete("eligible_pool") }
    assert_raises(SubmissionAudit::Invalid) { audit.call }
  end

  test "standalone executable rejects malformed JSON without exposing its contents" do
    Dir.mktmpdir do |dir|
      path = "#{dir}/bad.json"
      File.write(path, '{"secret":DO_NOT_PRINT}')
      err = StringIO.new
      assert_equal 2, SubmissionAudit.run(%w[providers operations decisions report].flat_map { |key| [ "--#{key}", path ] }, out: StringIO.new, err:)
      assert_includes err.string, "AUDIT FAIL"
      assert_not_includes err.string, "DO_NOT_PRINT"
    end
  end

  test "rehearsal uses final pipeline and removes all temporary final files" do
    before = DuoRoute::CLI::App::FINAL_FILES.to_h { |f| [ f, File.exist?(Rails.root.join(f)) ] }
    dirs_before = Dir.glob(File.join(Dir.tmpdir, "duoroute-rehearsal-*"))
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "rehearse-final", "--allow-reference-mismatch" ], out:, err: StringIO.new).run
    assert_includes out.string, "PASS WITH REFERENCE MISMATCH"
    assert_equal before, DuoRoute::CLI::App::FINAL_FILES.to_h { |f| [ f, File.exist?(Rails.root.join(f)) ] }
    assert_equal dirs_before, Dir.glob(File.join(Dir.tmpdir, "duoroute-rehearsal-*"))
    assert before.values.none?
  end

  test "readiness reports correct success and failure exit codes" do
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "readiness" ], out:, err: StringIO.new).run
    assert_equal "READY", out.string.lines.last.strip
    Dir.mktmpdir do |dir|
      out = StringIO.new
      assert_equal 2, DuoRoute::CLI::App.new([ "readiness" ], root: dir, out:, err: StringIO.new).run
      assert_equal "NOT READY", out.string.lines.last.strip
      assert_includes out.string, "required files"
    end
  end

  test "feasibility proves observed impossibility and never changes decisions" do
    input = fixture
    original = Marshal.dump(input[:decisions])
    report = DuoRoute::Reporting::GoalFeasibility.call(providers: input[:providers]["providers"], operations: input[:operations], decisions: input[:decisions])
    assert_equal "achieved", report["alpha"]["status"]
    assert_equal original, Marshal.dump(input[:decisions])
    data = providers_data([ provider(limit_amount_max: 100) ])
    result = DuoRoute::Runner.new(providers_data: data, operations: [ operation ], config: config).call
    row = result.report["goal_feasibility"]["alpha"]
    assert_equal false, row["target_reachable_on_observed_path"]
    assert_equal 0, row["observed_upper_share_pct"]
    assert_equal 1, row["blocking_constraints"]["amount_exceeds_limit"]
    recommendation = result.report["recommendation_details"].find { |detail| detail["provider"] == "alpha" }
    assert_equal 0, recommendation["observed_eligibility"]["eligible_operations"]
    assert_includes recommendation["proposed_action"], "amount_exceeds_limit"
    data = providers_data([ provider("alpha", traffic_percentage: 50), provider("beta", traffic_percentage: 50) ])
    over = DuoRoute::Runner.new(providers_data: data, operations: [ operation ], config: config,
      outcomes: { "default" => { "result" => "approved" } }).call
    assert_nil over.report["goal_feasibility"]["alpha"]["target_reachable_on_observed_path"]
    assert_equal "not_ruled_out", over.report["goal_feasibility"]["alpha"]["status"]
  end
end

class AuditLevelsTest < ActiveSupport::TestCase
  test "audit levels retain identical routing and independently valid states for multiple provider counts" do
    [ 1, 3, 10, 50 ].each do |count|
      bundle = DuoRoute::Generators::Scenario.new(name: "high_load", operations: 25, providers: count, seed: 42).call
      config = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml"))
      inputs = { providers_data: bundle["providers"], operations: bundle["operations"], config: }
      full = DuoRoute::Runner.new(**inputs).call
      %w[submission compact].each do |level|
        short = DuoRoute::Runner.new(**inputs, audit_level: level).call
        keys = %w[operation_id selected_provider simulated_result attempts latency_sec score score_breakdown eligible_pool fallback_used]
        stripped = ->(rows) { rows.map { |row| row.slice(*keys).merge("attempts" => row["attempts"].map { |a| a.except("simulation") }) } }
        assert_equal stripped.call(full.decisions), stripped.call(short.decisions)
        assert_equal full.report["goal_feasibility"], short.report["goal_feasibility"]
        assert SubmissionAudit.new(providers: bundle["providers"], operations: bundle["operations"], decisions: short.decisions, report: short.report).call
      end
      reversed = Marshal.load(Marshal.dump(bundle["providers"]))
      reversed["providers"].reverse!
      permuted = DuoRoute::Runner.new(**inputs.merge(providers_data: reversed)).call
      assert_equal full.decisions.map { |r| r.values_at("selected_provider", "simulated_result") }, permuted.decisions.map { |r| r.values_at("selected_provider", "simulated_result") }
    end
  end
end

class SubmissionRoundTripTest < ActiveSupport::TestCase
  test "decimal JSON emission round trips without binary tails or input mutation" do
    values = { "amount" => 7.66452, "latency" => 7.66452, "nested" => [ 0.1, 1.0 ] }
    before = Marshal.dump(values)
    assert_equal values, DuoRoute::Input::Loader.json_string(DuoRoute.pretty_json(values))
    assert_equal before, Marshal.dump(values)
    assert_raises(DuoRoute::Error) { DuoRoute.pretty_json({ "value" => Float::INFINITY }) }
  end

  test "independent state reconstruction supports held timeouts commit and rollback" do
    [ nil, "approved", "rejected" ].each do |status|
      data = providers_data
      ops = [ operation, operation("op_2", created_at: "2026-07-31T09:05:00+03:00") ]
      result = DuoRoute::Runner.new(providers_data: data, operations: ops, config: config(timeout: "hold_until_status"),
        outcomes: { "outcomes" => { "op_1:alpha" => { "result" => "expired", "latency_sec" => 7.66452, "status_check_result" => status } },
          "default" => { "result" => "approved", "latency_sec" => 2 } }).call
      assert SubmissionAudit.new(providers: data, operations: ops, decisions: result.decisions, report: result.report).call
      assert_equal result.decisions, DuoRoute::Input::Loader.json_string(DuoRoute.pretty_json(result.decisions))
    end
  end

  test "schema accepts supported shorthand and nested outcomes" do
    require_relative "../../script/check_schemas"
    schema = JSON.parse(Rails.root.join("schemas/outcomes.schema.json").read)
    [ { "op:alpha" => "approved" }, { "outcomes" => { "op" => { "alpha" => "expired" } }, "default" => "approved" } ].each do |value|
      assert_empty SchemaCheck.validate(value, schema)
    end
  end

  test "robustness evidence retains all predeclared cases without holdout tuning" do
    evidence = DuoRoute::Input::Loader.json_file(Rails.root.join("artifacts/verification/default_strategy_evaluation.json"))["robustness"]
    assert_equal 2064, evidence["run_count"]
    assert_equal 48, evidence["order_checks"]
    assert_equal [ 1, 3, 10, 50 ], evidence["provider_counts"]
    assert_equal false, evidence["default_changed"]
    assert_empty evidence["paired_holdout_dominators"]
    result = DuoRoute::Evaluation::Robustness.new.summarize(evidence["results"], order_checks: 48)
    assert_equal evidence["holdout_pareto_candidates"], result["holdout_pareto_candidates"]
  end
end
