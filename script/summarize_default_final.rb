#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
path = ARGV.first
abort "Укажите путь к исследованию: ruby #{File.basename(__FILE__)} PATH" unless ARGV.length == 1
abort "Файл исследования не найден: #{path}" unless File.file?(path)
report = JSON.parse(File.read(path))
abort "Исследование не завершено" unless report["status"] == "complete"
report["aggregates"].each do |split, candidates|
  puts split
  candidates.each do |name, row|
    m, r = row.values_at("metrics", "regret")
    puts [ name, m["failure_rate_pct"]["mean"], r["failure_rate_pct"]["worst"], m["fallback_rate_pct"]["mean"], r["fallback_rate_pct"]["worst"], m["average_latency_sec"]["mean"], m["count_absolute_deviation_pp"]["mean"], row["pareto_count"] ].join("\t")
  end
end
puts report["decision"].inspect
