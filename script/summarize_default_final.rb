#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
require_relative "../lib/duo_route/evaluation/final_study"
path = "artifacts/verification/DEFAULT_STRATEGY_FINAL_EVALUATION.json"
report = JSON.parse(File.read(path))
raise "study incomplete" unless report["status"] == "complete"
study = DuoRoute::Evaluation::FinalStudy.new
# All candidates have the same applicable objectives. Removing neutral empty
# coordinates must not alter the selection frozen before holdout.
validation = report["aggregates"]["validation"]
selected = validation.reject { |name, _| name == "auto_probe" }.min_by { |name, v| study.selection_key(v) + [ name ] }.first
raise "selection changed" unless selected == report["decision"]["candidate"]
report["decision"]["holdout_selection_key"] = study.selection_key(report["aggregates"]["holdout"][selected])
report["decision"]["holdout_balanced_key"] = study.selection_key(report["aggregates"]["holdout"]["balanced"])
report["aggregates"].each do |split, candidates|
  candidates.each do |name, summary|
    values = report["results"].select { |r| r["split"] == split && r["candidate"] == name }.map { |r| r["approval_rate_pct"] }
    summary["metrics"]["approval_rate_pct"] = study.statistics(values).merge("best" => values.max, "worst" => values.min)
  end
end
report["public_diagnosis"] = JSON.parse(File.read("tmp/public-diagnosis.json"))
report["benchmark"] = JSON.parse(File.read("tmp/final-benchmark.json"))
report["benchmark"]["time_output"] = File.read("tmp/final-benchmark.time")
report["specification_sha256"] = Digest::SHA256.file(ENV.fetch("DUOROUTE_SPECIFICATION_PATH")).hexdigest
report["pareto_by_scenario"] = report["results"].group_by { |r| r["scenario"] }.transform_values do |rows|
  objectives = %w[failure_rate_pct fallback_rate_pct average_latency_sec count_absolute_deviation_pp volume_absolute_deviation_pp turnover_gap_pct commission_pct capacity_pressure_pct rpm_pressure_pct unallocated_operations]
  rows.reject do |row|
    rows.any? do |other|
      active = objectives.select { |m| !row[m].nil? && !other[m].nil? }
      active.all? { |m| other[m] <= row[m] + 1e-9 } && active.any? { |m| other[m] < row[m] - 1e-9 }
    end
  end.map { |r| r["candidate"] }
end
report["limitations"] = report["methodology"]["limitations"] + [ "Auto probe uses known family labels; no production selector for unknown inputs is implemented", "Browser runtime found no connected browsers", "Dependency audit used local advisory database; importmap cannot audit unversioned vendored chart.js" ]
File.write(path, DuoRoute.pretty_json(report))
report["aggregates"].each do |split, candidates|
  puts split
  candidates.each do |name, row|
    m, r = row.values_at("metrics", "regret")
    puts [ name, m["failure_rate_pct"]["mean"], r["failure_rate_pct"]["worst"], m["fallback_rate_pct"]["mean"], r["fallback_rate_pct"]["worst"], m["average_latency_sec"]["mean"], m["count_absolute_deviation_pp"]["mean"], row["pareto_count"] ].join("\t")
  end
end
puts report["decision"].inspect
