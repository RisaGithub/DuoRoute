# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CliTest < ActiveSupport::TestCase
  test "help validate and unknown command return useful exit codes" do
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "help" ], out:).run
    assert_includes out.string, "final"
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "validate" ], out:).run
    assert_includes out.string, '"status": "valid"'
    assert_equal 2, DuoRoute::CLI::App.new([ "nope" ], out: StringIO.new, err: StringIO.new).run
  end

  test "route writes valid outputs atomically and never overwrites input" do
    Dir.mktmpdir do |dir|
      decisions = File.join(dir, "decisions.json")
      report = File.join(dir, "report.json")
      code = DuoRoute::CLI::App.new([ "route", "--quiet", "--decisions", decisions, "--report", report ], out: StringIO.new, err: StringIO.new).run
      assert_equal 0, code
      assert_empty DuoRoute::Reporting::OutputValidator.new.decisions(JSON.parse(File.read(decisions)), operation_ids: (101..110).map { |n| "op_#{n}" })
      assert_empty Dir.glob("#{dir}/*.tmp-*")
      input = Rails.root.join("data/examples/providers.json").to_s
      assert_equal 2, DuoRoute::CLI::App.new([ "route", "--quiet", "--decisions", input, "--report", report ], out: StringIO.new, err: StringIO.new).run
    end
  end

  test "final refuses misleading filename and leaves existing artifacts untouched" do
    decisions = Rails.root.join("routing_decisions_test.json")
    report = Rails.root.join("routing_report_test.json")
    original_decisions = decisions.exist? ? decisions.read : nil
    original_report = report.exist? ? report.read : nil
    code = DuoRoute::CLI::App.new([ "final", "--operations", "data/examples/operations_queue_10.json" ], out: StringIO.new, err: StringIO.new).run
    assert_equal 2, code
    original_decisions.nil? ? assert_not(decisions.exist?) : assert_equal(original_decisions, decisions.read)
    original_report.nil? ? assert_not(report.exist?) : assert_equal(original_report, report.read)
  end

  test "final accepts only exact queue name and atomically preserves old pair on validation failure" do
    Dir.mktmpdir do |dir|
      operations = File.join(dir, "operations_queue_test.json")
      providers = File.join(dir, "providers.json")
      routing_config = File.join(dir, "final.yml")
      outcomes = Rails.root.join("data/examples/demo_outcomes.json").to_s
      FileUtils.cp(Rails.root.join("data/examples/operations_queue_10.json"), operations)
      FileUtils.cp(Rails.root.join("data/examples/providers.json"), providers)
      FileUtils.cp(Rails.root.join("config/routing/final.yml"), routing_config)
      args = [ "final", "--operations", operations, "--providers", providers, "--config", routing_config,
        "--outcomes", outcomes, "--quiet" ]
      assert_equal 0, DuoRoute::CLI::App.new(args, root: dir, out: StringIO.new, err: StringIO.new).run
      decisions = File.join(dir, "routing_decisions_test.json")
      report = File.join(dir, "routing_report_test.json")
      assert_equal 10, JSON.parse(File.read(decisions)).length
      before = [ File.read(decisions), File.read(report) ]
      File.write(operations, "[]")
      assert_equal 2, DuoRoute::CLI::App.new(args, root: dir, out: StringIO.new, err: StringIO.new).run
      assert_equal before, [ File.read(decisions), File.read(report) ]
      assert_empty Dir.glob("#{dir}/*.{tmp,backup}-*")
    end
  end

  test "generate compare and explain smoke" do
    Dir.mktmpdir do |dir|
      assert_equal 0, DuoRoute::CLI::App.new([ "generate", "--scenario", "timeouts", "--operations", "5", "--providers", "2", "--output", dir ], out: StringIO.new).run
      assert File.exist?(File.join(dir, "outcomes.json"))
    end
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "compare", "--presets", "balanced,cascade" ], out:).run
    assert_equal 2, JSON.parse(out.string)["results"].length
    out = StringIO.new
    assert_equal 0, DuoRoute::CLI::App.new([ "explain", "--decisions", Rails.root.join("routing_decisions.json").to_s, "--operation", "op_103" ], out:).run
    assert_equal "op_103", JSON.parse(out.string)["operation_id"]
  end
end
