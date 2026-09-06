# frozen_string_literal: true

module DuoRoute
  module Evaluation
    # This is an offline experiment. None of its queue aggregates enter Engine.
    class DefaultStrategy
      ROOT = File.expand_path("../../..", __dir__)
      SCENARIOS = %w[normal hard_limits conflicting_goals high_load fallback timeouts stress].freeze
      SEEDS = [ 42, 17 ].freeze
      HOLDOUT_SEEDS = [ 101, 309 ].freeze
      CANDIDATES = {
        "legacy" => { "count_share" => 2.0, "volume_share" => 1.8, "cascade" => 0.6, "preferred_amount" => 0.8,
          "conversion" => 1.2, "load_safe" => 1.3, "intensity" => 0.5, "turnover_commitment" => 1.4, "economy" => 0.7 },
        "reliability" => { "count_share" => 2, "volume_share" => 2, "conversion" => 4, "load_safe" => 2,
          "intensity" => 2, "turnover_commitment" => 2, "latency" => 1, "economy" => 0.5 },
        "distribution" => { "count_share" => 4, "volume_share" => 4, "conversion" => 2, "load_safe" => 2,
          "intensity" => 1, "turnover_commitment" => 2, "latency" => 0.5, "economy" => 0.25 }
      }.freeze

      def call
        candidates = CANDIDATES.flat_map do |name, weights|
          [ false, true ].map { |calibrated| { "name" => "#{name}_#{calibrated ? 'calibrated' : 'snapshot'}", "weights" => weights, "calibrated" => calibrated } }
        end
        training = evaluate(candidates, SEEDS, [ 40, 160 ], "training")
        ranked = candidates.sort_by { |candidate| quality(training.select { |row| row["candidate"] == candidate["name"] }) + [ candidate["name"] ] }
        selected = ranked.first
        holdout = evaluate(candidates, HOLDOUT_SEEDS, [ 90 ], "holdout")
        {
          "protocol" => "Fixed candidates and lexicographic macro means; holdout never selects weights",
          "objective_order" => %w[fallback_rate_pct failure_rate_pct share_error_pp turnover_deficit_pct capacity_pressure_pct average_latency_sec negative_margin_spread],
          "seeds" => SEEDS, "holdout_seeds" => HOLDOUT_SEEDS, "sizes" => [ 40, 160 ], "holdout_sizes" => [ 90 ],
          "calibration" => { "minimum_samples" => 20, "prior_strength" => 30 },
          "selected_candidate" => selected["name"], "selected_weights" => selected["weights"], "selected_calibration" => selected["calibrated"],
          "ranking" => ranked.map { |candidate| { "candidate" => candidate["name"], "training_quality" => quality(training.select { |row| row["candidate"] == candidate["name"] }), "holdout_quality" => quality(holdout.select { |row| row["candidate"] == candidate["name"] }) } },
          "results" => training + holdout
        }
      end

      private

      def evaluate(candidates, seeds, sizes, split)
        rows = []
        seeds.each do |seed|
          sizes.each do |size|
            SCENARIOS.each_with_index do |scenario, index|
              bundle = Generators::Scenario.new(name: scenario, operations: size, providers: split == "holdout" ? 6 : 4, seed:).call
              # Holdout shifts amount/bank distribution and availability, not just RNG.
              if split == "holdout"
                bundle["operations"].each_with_index do |operation, i|
                  operation["amount"] = i.even? ? 500 : 50_000
                  operation["bank"] = i.even? ? "alfa" : "unknown_bank"
                end
                bundle["providers"]["providers"][0]["status"] = "paused"
                bundle["providers"]["providers"][1]["banks"] = [ "alfa" ]
              end
              headers = %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
              history = bundle["history"].map { |row| headers.zip(row).to_h }
              candidates.each do |candidate|
                config = Input::Loader.config_file(File.join(ROOT, "config/routing/default.yml"))
                config["presets"]["balanced"] = { "weights" => candidate["weights"], "policy_priorities" => candidate["weights"].keys }
                config["calibration"] = { "enabled" => candidate["calibrated"], "minimum_samples" => 20, "prior_strength" => 30 }
                outcomes = scenario == "timeouts" ? bundle["outcomes"] : nil
                result = Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], history:, config:, seed:, outcomes:).call
                rows << metrics(result, candidate["name"], scenario, size, seed, split)
              end
            end
          end
        end
        # The public queue is an additional small case, never the only objective.
        candidates.each do |candidate|
          config = Input::Loader.config_file(File.join(ROOT, "config/routing/default.yml"))
          config["presets"]["balanced"] = { "weights" => candidate["weights"], "policy_priorities" => candidate["weights"].keys }
          config["calibration"] = { "enabled" => candidate["calibrated"], "minimum_samples" => 20, "prior_strength" => 30 }
          result = Runner.new(providers_data: Input::Loader.json_file(File.join(ROOT, "data/providers.json")),
            operations: Input::Loader.json_file(File.join(ROOT, "data/operations_queue_10.json")),
            history: Input::Loader.csv_file(File.join(ROOT, "data/operations_history.csv")), config:, seed: 42).call
          rows << metrics(result, candidate["name"], "public", 10, 42, split) if split == "training"
        end
        rows
      end

      def metrics(result, candidate, scenario, size, seed, split)
        report = result.report
        errors = %w[distribution volume_distribution].filter_map { |key| Reporting::ComparisonMetrics.deviation(report[key]) }
        deficits = report["turnover_commitments"].values.filter_map do |row|
          next unless row["minimum"]&.positive?
          [ (row["minimum"] - row["actual"]).to_f / row["minimum"] * 100, 0 ].max
        end
        pressure = report["capacity_utilization"].values.filter_map { |row| row["daily_utilization_pct"] }
        {
          "candidate" => candidate, "scenario" => scenario, "size" => size, "seed" => seed, "split" => split,
          "fallback_rate_pct" => report["fallback_rate_pct"], "failure_rate_pct" => 100 - report["approval_rate_pct"],
          "share_error_pp" => (errors.empty? ? nil : mean(errors)), "turnover_deficit_pct" => mean(deficits),
          "capacity_pressure_pct" => mean(pressure), "average_latency_sec" => report["average_latency_sec"],
          "negative_margin_spread" => -result.decisions.sum { |decision| decision.dig("score_breakdown", "economy", "raw_value").to_f } / size,
          "invariants" => "passed"
        }
      end

      def quality(rows)
        %w[fallback_rate_pct failure_rate_pct share_error_pp turnover_deficit_pct capacity_pressure_pct average_latency_sec negative_margin_spread].map do |metric|
          mean(rows.map { |row| row[metric] }).round(6)
        end
      end

      def mean(values) = values.empty? ? 0.0 : values.sum.fdiv(values.length)
    end
  end
end
