#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
require_relative "../lib/duo_route/evaluation/final_study"
require_relative "../lib/duo_route/evaluation/pair_audit"
study = DuoRoute::Evaluation::FinalStudy.new
data = study.bundle("public", 10, 42)
config = DuoRoute::Input::Loader.config_file("config/routing/final.yml")
rows = {}
results = []
(DuoRoute::StrategyCatalog.all.keys + [ "balanced" ]).each do |name|
  result = study.run(data, name, 42, "public", audit_level: "full")
  results << result
  rows[name] = { "metrics" => study.metrics(data, result), "decisions" => result.decisions.select { |d| %w[op_101 op_105 op_108].include?(d["operation_id"]) } }
end
DuoRoute::Evaluation::PairAudit.call(results)
ablations = config["presets"]["balanced"]["weights"].keys.to_h do |policy|
  changed = DuoRoute::Configuration.copy(config)
  changed["presets"]["balanced"]["weights"][policy] = 0
  result = DuoRoute::Runner.new(providers_data: data["providers"], operations: data["operations"], history: data["history"], config: changed, seed: 42).call
  [ "without_#{policy}", study.metrics(data, result) ]
end
changed = DuoRoute::Configuration.copy(data)
changed["providers"]["providers"].each { |p| %w[daily_approved_amount in_progress_count in_progress_amount].each { |k| p[k] = 0 } }
ablations["zero_initial_load"] = study.metrics(changed, study.run(changed, "balanced", 42, "public"))
changed = DuoRoute::Configuration.copy(config)
changed["presets"]["balanced"]["policy_priorities"].reverse!
result = DuoRoute::Runner.new(providers_data: data["providers"], operations: data["operations"], history: data["history"], config: changed, seed: 42).call
ablations["reverse_tie_break"] = study.metrics(data, result)
changed = DuoRoute::Configuration.copy(data)
changed["operations"].reverse!
result = study.run(changed, "balanced", 42, "public", audit_level: "full")
raise "input order changed chronological routing" unless result.decisions == results.last.decisions
changed["operations"].each_with_index { |op, i| op["created_at"] = (Time.iso8601(changed["providers"]["snapshot_at"]) + i * 60).iso8601 }
ablations["reverse_chronological_schedule"] = study.metrics(changed, study.run(changed, "balanced", 42, "public"))
File.write("tmp/public-diagnosis.json", DuoRoute.pretty_json({ "strategies" => rows, "ablations" => ablations, "pair_audit" => "passed", "input_order_check" => "passed" }))
puts DuoRoute.pretty_json(ablations.transform_values { |m| m.slice("approval_rate_pct", "average_latency_sec", "count_absolute_deviation_pp") })
