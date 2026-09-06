# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/duo_route/evaluation/final_study"
require_relative "../../lib/duo_route/evaluation/pair_audit"

class FinalStudyTest < ActiveSupport::TestCase
  def setup
    @study = DuoRoute::Evaluation::FinalStudy.new
    @data = @study.bundle("normal", 10, 113)
  end

  test "repeats and reversed strategy execution produce identical decisions and paired outcomes" do
    names = DuoRoute::StrategyCatalog.all.keys + [ "balanced" ]
    before = DuoRoute.pretty_json(@data)
    first = names.to_h { |n| [ n, @study.run(@data, n, 113, "normal") ] }
    second = names.reverse.to_h { |n| [ n, @study.run(@data, n, 113, "normal") ] }
    assert DuoRoute::Evaluation::PairAudit.call(first.values)
    names.each { |n| assert_equal first[n].decisions, second[n].decisions }
    assert_equal before, DuoRoute.pretty_json(@data)
    assert_equal @data, @study.bundle("normal", 10, 113)
  end

  test "mutations to paired seed input profile outcomes and missing targets are detected" do
    original = @study.run(@data, "balanced", 113, "normal")
    %w[seed operations_sha256 simulation].each do |key|
      mutant = Marshal.load(Marshal.dump(original))
      mutant.manifest[key] = "broken"
      assert_raises(DuoRoute::Error) { DuoRoute::Evaluation::PairAudit.call([ original, mutant ]) }
    end
    mutant = Marshal.load(Marshal.dump(original))
    mutant.manifest["resolved_configuration"]["provider_overrides"] = { "provider_1" => { "volume_share_pct" => 0 } }
    assert_raises(DuoRoute::Error) { DuoRoute::Evaluation::PairAudit.call([ original, mutant ]) }
    mutant = Marshal.load(Marshal.dump(original))
    attempt = mutant.decisions.first["attempts"].find { |a| a.key?("result") }
    attempt["latency_sec"] += 1
    assert_raises(DuoRoute::Error) { DuoRoute::Evaluation::PairAudit.call([ original, mutant ]) }
    mutant = Marshal.load(Marshal.dump(original))
    row = mutant.report["volume_distribution"].values.last
    row["deviation_pp"] = 0
    assert_raises(DuoRoute::Error) { DuoRoute::Evaluation::PairAudit.call([ mutant ]) }
    mutant = Marshal.load(Marshal.dump(original))
    row = mutant.report["distribution"].values.last
    row["share_pct"] = 20
    row["deviation_pp"] = nil
    assert_raises(DuoRoute::Error) { DuoRoute::Evaluation::PairAudit.call([ mutant ]) }
  end

  test "independent audit detects attribution to initial candidate and invalid admission" do
    data = providers_data([ provider("alpha", traffic_percentage: 100) ])
    result = DuoRoute::Runner.new(providers_data: data, operations: [ operation ], config:,
      outcomes: { "outcomes" => { "op_1:alpha" => "rejected" }, "default" => "approved" }).call
    mutant = Marshal.load(Marshal.dump(result))
    mutant.decisions.first["selected_provider"] = "alpha"
    assert_raises(SubmissionAudit::Invalid) do
      SubmissionAudit.new(providers: data, operations: [ operation ], decisions: mutant.decisions, report: mutant.report).call
    end
    mutant = Marshal.load(Marshal.dump(result))
    mutant.decisions.first["attempts"].find { |a| a.key?("result") }["provider"] = "unknown"
    assert_raises(SubmissionAudit::Invalid) do
      SubmissionAudit.new(providers: data, operations: [ operation ], decisions: mutant.decisions, report: mutant.report).call
    end
  end

  test "selection evidence reports actual settings and identifies overrides" do
    result = @study.run(@data, "balanced", 113, "normal")
    evidence = result.manifest.fetch("strategy_selection")
    assert_equal result.manifest.dig("resolved_configuration", "presets", "balanced", "weights"), evidence["actual_weights"]
    assert_equal evidence, result.report["strategy_selection"]
    assert evidence["matches_evaluated_default"]
    altered = DuoRoute::Configuration.copy(result.manifest["resolved_configuration"])
    altered["presets"]["balanced"]["policy_priorities"].reverse!
    assert_not DuoRoute::DefaultSelection.evidence("balanced", altered)["matches_evaluated_default"]
    result = @study.run(@data, "latency_only", 113, "normal")
    assert_equal({ "latency" => 1 }, result.manifest.dig("strategy_selection", "actual_weights"))
    assert_equal "latency_only", result.manifest.dig("strategy_selection", "strategy")
  end

  test "unavailable reserve fails closed for every candidate" do
    data = @study.bundle("fallback", 10, 113)
    data["providers"]["providers"].last["status"] = "paused"
    (DuoRoute::StrategyCatalog.all.keys + [ "balanced" ] + DuoRoute::Evaluation::FinalStudy::EXTRA.keys).each do |name|
      assert_raises(DuoRoute::Error) { @study.run(data, name, 113, "fallback") }
    end
  end

  test "bad inputs fail for every candidate instead of yielding optimistic metrics" do
    data = @study.bundle("normal", 10, 113)
    data["operations"][0]["amount"] = -1
    (DuoRoute::StrategyCatalog.all.keys + [ "balanced" ] + DuoRoute::Evaluation::FinalStudy::EXTRA.keys).each do |name|
      assert_raises(DuoRoute::InputError) { @study.run(data, name, 113, "normal") }
    end
  end
end
