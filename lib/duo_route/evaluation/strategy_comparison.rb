# frozen_string_literal: true

module DuoRoute
  module Evaluation
    # A diagnostic study, not a production selector or a source of tuned weights.
    class StrategyComparison
      SCENARIOS = %w[normal hard_limits conflicting_goals high_load fallback timeouts stress].freeze
      SEEDS = [ 17, 42, 101, 309 ].freeze
      SIZES = [ 3, 40, 1000 ].freeze

      def call
        require_relative "../../../script/audit_submission"
        candidates = StrategyCatalog.all.keys + [ "balanced" ]
        rows = []
        SCENARIOS.each do |scenario|
          SIZES.each do |size|
            bundle = Generators::Scenario.new(name: scenario, operations: size, providers: 4, seed: 17).call
            headers = %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
            history = bundle["history"].map { |row| headers.zip(row).to_h }
            SEEDS.each do |seed|
              candidates.each do |candidate|
                config = Input::Loader.config_file(File.join(CLI::App::ROOT, "config/routing/final.yml"))
                result = Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], history:, config:, seed:,
                  preset: candidate, audit_level: "compact", outcomes: scenario == "timeouts" ? bundle["outcomes"] : nil).call
                SubmissionAudit.new(providers: bundle["providers"], operations: bundle["operations"], decisions: result.decisions, report: result.report).call
                rows << { "scenario" => scenario, "size" => size, "seed" => seed, "candidate" => candidate,
                  "approval_rate_pct" => result.report["approval_rate_pct"], "fallback_rate_pct" => result.report["fallback_rate_pct"],
                  "average_latency_sec" => result.report["average_latency_sec"] }.merge(Reporting::ComparisonMetrics.call(result.report))
              end
            end
          end
        end
        paired = candidates.reject { |candidate| candidate == "balanced" }.select do |candidate|
          pairs = rows.select { |r| r["candidate"] == candidate }.zip(rows.select { |r| r["candidate"] == "balanced" })
          pairs.all? { |a, b| quality(a).zip(quality(b)).all? { |x, y| x <= y } } &&
            pairs.any? { |a, b| quality(a).zip(quality(b)).any? { |x, y| x < y } }
        end
        # Probe selecting on seed 17, then measure the same choice on unseen outcomes.
        probe = rows.group_by { |r| r.values_at("scenario", "size") }.flat_map do |(scenario, size), group|
          selected = group.select { |r| r["seed"] == SEEDS.first }.min_by { |r| quality(r) + [ r["candidate"] ] }["candidate"]
          SEEDS.drop(1).map do |seed|
            chosen = group.find { |r| r["candidate"] == selected && r["seed"] == seed }
            baseline = group.find { |r| r["candidate"] == "balanced" && r["seed"] == seed }
            { "scenario" => scenario, "size" => size, "seed" => seed, "chosen" => selected,
              "quality" => quality(chosen), "baseline_quality" => quality(baseline), "comparison" => quality(chosen) <=> quality(baseline) }
          end
        end
        { "protocol" => "Same input, config, history and operation/provider random outcomes; no catalog overrides; independent semantic audit of every run",
          "candidates" => candidates, "seeds" => SEEDS, "sizes" => SIZES, "run_count" => rows.length,
          "paired_dominators" => paired, "auto_probe" => { "selection_seed" => SEEDS.first, "holdout_seeds" => SEEDS.drop(1),
            "wins" => probe.count { |r| r["comparison"] == -1 }, "ties" => probe.count { |r| r["comparison"] == 0 },
            "losses" => probe.count { |r| r["comparison"] == 1 }, "results" => probe }, "results" => rows }
      end

      private

      def quality(row)
        [ -row["approval_rate_pct"], row["fallback_rate_pct"], row["count_absolute_deviation_pp"],
          row["volume_absolute_deviation_pp"], row["average_latency_sec"] ].compact
      end
    end
  end
end
