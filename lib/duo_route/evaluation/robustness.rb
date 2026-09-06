# frozen_string_literal: true

module DuoRoute
  module Evaluation
    class Robustness < DefaultStrategy
      METRICS = %w[fallback_rate_pct failure_rate_pct share_error_pp turnover_deficit_pct capacity_pressure_pct average_latency_sec negative_margin_spread].freeze
      FACTORS = CANDIDATES.fetch("reliability").freeze

      def call
        require_relative "../../../script/audit_submission"
        variants = { "default" => FACTORS, "legacy" => CANDIDATES["legacy"], "distribution" => CANDIDATES["distribution"] }
        FACTORS.each do |factor, weight|
          [ -20, -10, 10, 20 ].each { |change| variants["#{factor}_#{change}"] = FACTORS.merge(factor => weight * (1 + change / 100.0)) }
          variants["without_#{factor}"] = FACTORS.merge(factor => 0)
        end
        rows = []
        order_checks = 0
        [ [ "training", [ 17, 42 ] ], [ "holdout", [ 101, 309 ] ] ].each do |split, seeds|
          seeds.each do |seed|
            [ 1, 3, 10, 50 ].each do |count|
              [ 12, 60, 180 ].each_with_index do |size, scenario_index|
                scenario = %w[normal hard_limits conflicting_goals][scenario_index]
                bundle = Generators::Scenario.new(name: scenario, operations: size, providers: count, seed:).call
                external = bundle["providers"]["providers"].reject { |p| p["payment_system"] == "spacepayments" }
                external.each_with_index do |p, index|
                  p["payment_system"] = "channel_#{count - index}" if split == "holdout"
                  p["conversion_24h"] = [ 0.45, 0.75, 0.98 ][index % 3]
                  p["provider_margin_pct"] = 0.5 + index % 5 * 0.1
                  p["banks"] = index.even? ? [ "sberbank", "alfa" ] : []
                  p["requests_per_minute_limit"] = [ 1, 7, 60 ][(index + scenario_index) % 3]
                  p["daily_approved_amount"] = scenario_index == 1 ? p["daily_amount_limit"] - 500 : (index.even? ? 0 : 100_000)
                  p["daily_turnover_min"] = index.zero? ? p["daily_amount_limit"] * 2 : 200_000
                  p["volume_share_pct"] = index.zero? ? 100 : 0
                end
                bundle["operations"].each_with_index do |op, index|
                  op["amount"] = [ 500, 50_000, 200_001 ][(index + scenario_index) % 3]
                  op["bank"] = [ "sberbank", "alfa", "unknown_bank" ][index % 3]
                  op["created_at"] = (Time.iso8601(bundle["providers"]["snapshot_at"]) + index * (split == "holdout" ? 3600 : 2)).iso8601
                end
                baseline = nil
                variants.each do |name, weights|
                  config = Input::Loader.config_file(File.join(ROOT, "config/routing/default.yml"))
                  config["presets"]["balanced"] = { "weights" => weights, "policy_priorities" => FACTORS.keys }
                  result = Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], config:, seed:, audit_level: "compact").call
                  SubmissionAudit.new(providers: bundle["providers"], operations: bundle["operations"], decisions: result.decisions, report: result.report).call
                  row = metrics(result, name, "#{scenario}_p#{count}", size, seed, split)
                  row["external_providers"] = count
                  rows << row
                  if name == "default"
                    baseline = result.decisions.map { |d| d.values_at("selected_provider", "simulated_result") }
                    reversed = Configuration.copy(bundle["providers"])
                    reversed["providers"].reverse!
                    other = Runner.new(providers_data: reversed, operations: bundle["operations"], config:, seed:, audit_level: "compact").call
                    raise Error, "provider order affects routing" unless baseline == other.decisions.map { |d| d.values_at("selected_provider", "simulated_result") }
                    order_checks += 1
                  end
                end
              end
            end
          end
        end
        summarize(rows, order_checks:)
      end

      def summarize(rows, order_checks:)
        summaries = rows.group_by { |row| [ row["split"], row["candidate"] ] }.map do |(split, candidate), group|
          { "split" => split, "candidate" => candidate, "metrics" => METRICS.to_h do |metric|
            values = group.map { |row| row[metric] }.sort
            avg = mean(values)
            [ metric, { "mean" => avg.round(6), "median" => ((values[(values.size - 1) / 2] + values[values.size / 2]) / 2.0).round(6),
              "p95" => values[(values.size * 0.95).ceil - 1], "worst" => values.last, "best" => values.first,
              "range" => (values.last - values.first).round(6), "stddev" => Math.sqrt(mean(values.map { |v| (v - avg)**2 })).round(6) } ]
          end }
        end
        holdout = summaries.select { |row| row["split"] == "holdout" }
        objectives = METRICS.first(6)
        dominates = lambda do |a, b|
          objectives.all? { |m| a["metrics"][m]["mean"] <= b["metrics"][m]["mean"] } && objectives.any? { |m| a["metrics"][m]["mean"] < b["metrics"][m]["mean"] }
        end
        frontier = holdout.reject { |b| holdout.any? { |a| dominates.call(a, b) } }.map { |row| row["candidate"] }
        defaults = rows.select { |row| row["split"] == "holdout" && row["candidate"] == "default" }
        paired_dominators = rows.select { |row| row["split"] == "holdout" }.group_by { |row| row["candidate"] }.filter_map do |name, group|
          pairs = group.zip(defaults)
          next unless pairs.all? { |a, b| objectives.all? { |m| a[m] <= b[m] } }
          name if pairs.any? { |a, b| objectives.any? { |m| a[m] < b[m] } }
        end
        { "protocol" => "Predeclared sensitivity ±10/20% and ablations; independent audit of every run. Holdout is diagnostic, never tunes weights.",
          "default_changed" => false, "weights" => FACTORS, "run_count" => rows.size, "order_checks" => order_checks,
          "provider_counts" => [ 1, 3, 10, 50 ], "renaming" => "Holdout uses renamed providers; responses can differ because simulation hashes provider names.",
          "pareto_objectives" => objectives, "holdout_pareto_candidates" => frontier,
          "paired_holdout_dominators" => paired_dominators,
          "default_on_mean_pareto_frontier" => frontier.include?("default"),
          "conclusion" => "Веса сохранены. Устойчивость локальных изменений оценивается по summaries; default не объявляется лучшим. Средние Pareto и попарное доминирование всех holdout-сценариев приведены отдельно.",
          "summaries" => summaries, "results" => rows }
      end
    end
  end
end
