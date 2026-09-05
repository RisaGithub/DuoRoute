# frozen_string_literal: true

require "test_helper"

class FinalSafetyTest < ActiveSupport::TestCase
  test "dry run uses default history and writes no final or audit artifacts" do
    final_fixture do |root, args|
      out = StringIO.new
      assert_equal 0, DuoRoute::CLI::App.new(args + [ "--dry-run", "--explain-summary" ], root:, out:, err: StringIO.new).run
      assert_includes out.string, "history"
      assert_includes out.string, "Dry-run успешен"
      assert_empty Dir.glob("#{root}/routing_*_test.json")
      assert_not File.exist?("#{root}/tmp/final_audit")
      assert_equal 0, DuoRoute::CLI::App.new(args, root:, out: StringIO.new, err: StringIO.new).run
      assert_equal %w[routing_decisions_test.json routing_report_test.json], Dir.glob("#{root}/routing*").map { |path| File.basename(path) }.sort
      assert File.file?("#{root}/tmp/final_audit/manifest.json")
      first = File.read("#{root}/routing_decisions_test.json")
      assert_equal 0, DuoRoute::CLI::App.new(args, root:, out: StringIO.new, err: StringIO.new).run
      assert_equal first, File.read("#{root}/routing_decisions_test.json")
    end
  end

  test "final missing or empty history preserves old files and accepts explicit snapshot" do
    final_fixture do |root, args|
      File.unlink("#{root}/data/operations_history.csv")
      File.write("#{root}/routing_decisions_test.json", "old decisions")
      File.write("#{root}/routing_report_test.json", "old report")
      err = StringIO.new
      assert_equal 2, DuoRoute::CLI::App.new(args, root:, out: StringIO.new, err:).run
      assert_includes err.string, "history"
      assert_equal "old decisions", File.read("#{root}/routing_decisions_test.json")
      assert_equal "old report", File.read("#{root}/routing_report_test.json")
      assert_equal 0, DuoRoute::CLI::App.new(args + [ "--simulation-source", "provider_snapshot", "--dry-run" ], root:, out: StringIO.new, err: StringIO.new).run
    end
  end

  test "injected second rename failure rolls back all artifacts" do
    final_fixture do |root, args|
      app = -> { DuoRoute::CLI::App.new(args, root:, out: StringIO.new, err: StringIO.new).run }
      assert_equal 0, app.call
      paths = Dir.glob("#{root}/routing*.json") + Dir.glob("#{root}/tmp/final_audit/*.json")
      before = paths.to_h { |path| [ path, File.read(path) ] }
      failing_app = Class.new(DuoRoute::CLI::App) do
        def rename_artifact(source, target)
          @rename_count = (@rename_count || 0) + 1
          raise Errno::ENOSPC if @rename_count == 2
          super
        end
      end
      assert_equal 2, failing_app.new(args, root:, out: StringIO.new, err: StringIO.new).run
      assert_equal before, paths.to_h { |path| [ path, File.read(path) ] }
      assert_empty Dir.glob("#{root}/**/*.{tmp,backup}-*")
    end
  end

  test "symlink and hardlink output aliases cannot overwrite inputs" do
    Dir.mktmpdir do |root|
      input = "#{root}/input.json"
      FileUtils.cp(Rails.root.join("data/providers.json"), input)
      before = File.read(input)
      [ File.method(:symlink), File.method(:link) ].each_with_index do |link, index|
        path = "#{root}/output#{index}.json"
        link.call(input, path)
        args = [ "route", "--providers", input, "--decisions", path, "--report", "#{root}/report.json" ]
        assert_equal 2, DuoRoute::CLI::App.new(args, out: StringIO.new, err: StringIO.new).run
        assert_equal before, File.read(input)
      end
    end
  end

  test "command help exits before reading files" do
    %w[final route validate compare generate explain].each do |command|
      assert_equal 0, DuoRoute::CLI::App.new([ command, "--help" ], out: StringIO.new, err: StringIO.new, root: "/nonexistent").run
    end
  end

  private

  def final_fixture
    Dir.mktmpdir("duoroute-final-fixture-") do |root|
      FileUtils.mkdir_p([ "#{root}/data", "#{root}/config/routing" ])
      FileUtils.cp(Rails.root.join("data/operations_queue_10.json"), "#{root}/operations_queue_test.json")
      %w[providers.json operations_history.csv].each { |name| FileUtils.cp(Rails.root.join("data", name), "#{root}/data/#{name}") }
      FileUtils.cp(Rails.root.join("config/routing/final.yml"), "#{root}/config/routing/final.yml")
      yield root, [ "final", "--quiet" ]
    end
  end
end
