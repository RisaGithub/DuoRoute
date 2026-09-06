#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
require_relative "../lib/duo_route/evaluation/final_study"
require_relative "../lib/duo_route/evaluation/pair_audit"
path = ARGV.first
abort "Укажите путь к исследованию: ruby #{File.basename(__FILE__)} PATH" unless ARGV.length == 1
abort "Файл исследования не найден: #{path}" unless File.file?(path)
report = JSON.parse(File.read(path))
abort "Исследование не завершено" unless report["status"] == "complete"
study = DuoRoute::Evaluation::FinalStudy.new
study.instance_variable_set(:@candidates, report["methodology"]["candidates"])
selected = report["decision"]["candidate"]
checks = 0
report["scenarios"].reverse_each do |scenario|
  data = study.bundle(scenario["family"], scenario["size"], scenario["seed"])
  names = [ selected, "balanced" ].uniq.reverse
  results = names.map do |candidate|
    result = study.run(data, candidate, scenario["seed"], scenario["family"])
    row = report["results"].find { |r| r["scenario"] == scenario["id"] && r["candidate"] == candidate }
    raise "non-reproducible decisions #{scenario['id']}/#{candidate}" unless study.digest(result.decisions) == row["decisions_sha256"]
    checks += 1
    result
  end
  DuoRoute::Evaluation::PairAudit.call(results)
  warn "replayed #{scenario['id']}"
end
report["paired_reproduction"] = { "runs" => checks, "scenario_pairs" => report["scenarios"].size, "order" => "reverse scenarios and candidates", "result" => "identical decisions SHA256; equal inputs, shared configuration, simulator profiles, targets and outcomes on overlapping attempts" }
File.write(path, DuoRoute.pretty_json(report))
puts report["paired_reproduction"].inspect
