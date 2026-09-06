#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"
require_relative "../lib/duo_route/evaluation/final_study"
path = ARGV.fetch(0, File.expand_path("../artifacts/verification/DEFAULT_STRATEGY_FINAL_EVALUATION.json", __dir__))
study = DuoRoute::Evaluation::FinalStudy.new
report = study.call(path:)
File.write(path, DuoRoute.pretty_json(report))
puts DuoRoute.pretty_json(report.slice("decision", "scenario_count", "runner_count", "deterministic_sha256"))
