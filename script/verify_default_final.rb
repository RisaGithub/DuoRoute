#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
checks = []
run = lambda do |name, command, expected = 0|
  output, status = Open3.capture2e(*command)
  path = "tmp/final-check-#{name}.log"
  File.write(path, output)
  checks << { "name" => name, "command" => command, "exit_code" => status.exitstatus, "expected_exit_code" => expected,
    "passed" => status.exitstatus == expected, "output" => output }
  warn "#{name}: #{status.exitstatus} (expected #{expected})"
end
run.call("tests", [ "bin/rails", "test" ])
run.call("rubocop", [ "bin/rubocop", "--no-parallel", "--cache", "false" ])
run.call("brakeman", [ "bundle", "exec", "brakeman", "--quiet", "--no-pager", "--exit-on-warn", "--exit-on-error" ])
run.call("dependency_audit", [ "bundle", "exec", "bundler-audit", "check" ])
run.call("importmap_audit", [ "bin/importmap", "audit" ])
run.call("zeitwerk", [ "bin/rails", "zeitwerk:check" ])
run.call("markdown_links", [ "ruby", "script/check_markdown_links.rb" ])
run.call("readiness", [ "bin/router", "readiness" ])
run.call("strict_rehearsal", [ "bin/router", "rehearse-final" ], 2)
run.call("allowed_rehearsal", [ "bin/router", "rehearse-final", "--allow-reference-mismatch" ])
run.call("seven_strategies", [ "bin/router", "compare", "--config", "config/routing/final.yml", "--seed", "42" ])
Dir.mktmpdir("duoroute-public-check-") do |dir|
  %w[history scripted].each do |mode|
    decisions = File.join(dir, "#{mode}-decisions.json")
    report = File.join(dir, "#{mode}-report.json")
    args = [ "bin/router", "route", "--providers", "data/providers.json", "--operations", "data/operations_queue_10.json", "--config", "config/routing/final.yml", "--history", "data/operations_history.csv", "--seed", "42", "--decisions", decisions, "--report", report, "--quiet" ]
    args += [ "--outcomes", "data/examples/demo_outcomes.json" ] if mode == "scripted"
    run.call("route_#{mode}", args)
    run.call("semantic_#{mode}", [ "ruby", "script/audit_submission.rb", "--providers", "data/providers.json", "--operations", "data/operations_queue_10.json", "--decisions", decisions, "--report", report, "--config", "#{report}.config.json" ])
    [ "script/validate_10.rb", ENV["DUOROUTE_PUBLIC_VALIDATOR_PATH"] ].compact.each_with_index do |validator, i|
      run.call("public_#{mode}_#{i}", [ "ruby", validator, decisions ], mode == "scripted" ? 0 : 1)
    end
    { "routing_decisions" => decisions, "routing_report" => report, "routing_config" => "#{report}.config.json" }.each do |schema, file|
      run.call("schema_#{mode}_#{schema}", [ "ruby", "script/check_schemas.rb", "schemas/#{schema}.schema.json", file ])
    end
  end
end
File.write("tmp/final-checks.json", DuoRoute.pretty_json(checks))
exit(checks.all? { |c| c["passed"] } ? 0 : 1)
