# frozen_string_literal: true

require "test_helper"
require_relative "../../script/audit_submission"

class ComparisonSemanticsTest < ActiveSupport::TestCase
  test "missing partial complete and explicit zero volume targets remain distinct" do
    [ [ nil, nil ], [ 40, 60 ], [ 40, nil ], [ 0, nil ] ].each do |targets|
      externals = %w[alpha beta].each_with_index.map do |name, i|
        provider(name, traffic_percentage: 50).tap { |p| p["volume_share_pct"] = targets[i] unless targets[i].nil? }
      end
      result = DuoRoute::Runner.new(providers_data: providers_data(externals), operations: [ operation ], config:,
        outcomes: { "default" => "approved" }).call
      metrics = DuoRoute::Reporting::ComparisonMetrics.call(result.report)
      names = %w[alpha beta].each_with_index.filter_map { |name, i| name unless targets[i].nil? }
      assert_equal names, metrics["volume_target_providers"]
      expected = result.report["volume_distribution"].values.filter_map { |row| row["deviation_pp"] }.sum(&:abs)
      if names.empty?
        assert_nil metrics["volume_absolute_deviation_pp"]
      else
        assert_equal expected, metrics["volume_absolute_deviation_pp"]
      end
      targets.each_with_index do |target, i|
        actual = result.report["volume_distribution"][%w[alpha beta][i]]["target_pct"]
        target.nil? ? assert_nil(actual) : assert_equal(target, actual)
      end
    end
  end

  test "CLI compares seven strategies without inventing catalog targets" do
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "compare", "--config", Rails.root.join("config/routing/final.yml").to_s ], out:, err: StringIO.new).run
    rows = JSON.parse(out.string).fetch("results")
    assert_equal DuoRoute::StrategyCatalog.all.keys, rows.map { |row| row["preset"] }
    rows.each do |row|
      assert_nil row["volume_absolute_deviation_pp"]
      assert_empty row["volume_target_providers"]
      assert_empty row["resolved_configuration"]["provider_overrides"]
    end
  end

  test "counterfactual outcomes do not depend on cascade position or call order" do
    simulator = DuoRoute::Simulation::Seeded.new(seed: 42)
    50.times do |i|
      op = operation("sample_#{i}")
      before = simulator.call(operation: op, provider: provider, attempt: 1)
      simulator.call(operation: operation("other"), provider: provider("beta"), attempt: 2)
      assert_equal before, simulator.call(operation: op, provider: provider, attempt: 4)
    end
  end

  test "cascade keeps every call and attributes report to final provider" do
    [ %w[approved], %w[rejected approved], %w[expired rejected approved], %w[rejected rejected approved] ].each do |statuses|
      data = providers_data([ provider("alpha", traffic_percentage: 50, priority: 1), provider("beta", traffic_percentage: 50, priority: 2) ])
      names = %w[alpha beta spacepayments]
      outcomes = names.zip(statuses).filter_map { |name, status| [ "op_1:#{name}", { "result" => status, "latency_sec" => 2 } ] if status }.to_h
      result = DuoRoute::Runner.new(providers_data: data, operations: [ operation ], config: config({ "cascade" => 1 }),
        outcomes: { "outcomes" => outcomes, "default" => "approved" }).call
      decision = result.decisions.first
      calls = decision["attempts"].select { |attempt| attempt.key?("result") }
      assert_equal statuses, calls.map { |attempt| attempt["result"] }
      assert_equal names.take(statuses.size), calls.map { |attempt| attempt["provider"] }
      assert calls.take(statuses.size - 1).all? { |attempt| attempt["decision"] == "skipped" && !attempt["reason"].empty? }
      assert_equal names[statuses.size - 1], decision["selected_provider"]
      assert_equal statuses.size == 3, decision["fallback_used"]
      assert_equal 1, result.report["distribution"][decision["selected_provider"]]["count"]
      assert_equal 1, result.report["distribution"].values.sum { |row| row["count"] }
      assert SubmissionAudit.new(providers: data, operations: [ operation ], decisions: result.decisions, report: result.report).call
    end
    data = providers_data
    result = DuoRoute::Runner.new(providers_data: data, operations: [ operation ], config:,
      outcomes: { "outcomes" => { "op_1:alpha" => "expired" }, "default" => "approved" }).call
    assert_equal "spacepayments", result.decisions.first["selected_provider"]
    assert_equal %w[expired approved], result.decisions.first["attempts"].filter_map { |a| a["result"] }
  end

  test "strict rehearsal fails visibly and allowed mismatch has separate status and cleans up" do
    before = Dir.glob(File.join(Dir.tmpdir, "duoroute-rehearsal-*"))
    [ false, true ].each do |allowed|
      out, err = StringIO.new, StringIO.new
      args = [ "rehearse-final" ] + (allowed ? [ "--allow-reference-mismatch" ] : [])
      assert_equal allowed ? 0 : 2, DuoRoute::CLI::App.new(args, out:, err:).run
      assert_includes out.string, "REFERENCE MISMATCH"
      assert_not_includes out.string, "REHEARSAL PASS"
      allowed ? assert_includes(out.string, "PASS WITH REFERENCE MISMATCH") : assert_includes(err.string, "--allow-reference-mismatch")
      assert_equal before, Dir.glob(File.join(Dir.tmpdir, "duoroute-rehearsal-*"))
    end
  end

  test "reference exception never tolerates unrelated validator failures" do
    app = DuoRoute::CLI::App.new([], out: StringIO.new, err: StringIO.new)
    status = Struct.new(:exitstatus).new(1)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "decisions.json")
      File.write(path, "[]")
      assert_not app.send(:reference_only_failure?, "❌ broken structure\n❌ Ошибок: 1", status, path)
    end
  end
end
