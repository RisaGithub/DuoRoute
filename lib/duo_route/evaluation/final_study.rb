# frozen_string_literal: true

require "objspace"
require_relative "../../../script/audit_submission"

module DuoRoute
  module Evaluation
    # Fixed protocol; selection is saved before any holdout outcome is computed.
    class FinalStudy
      ROOT = File.expand_path("../../..", __dir__)
      FAMILIES = %w[normal small whale skewed burst daily rpm progress unavailable requisites banks amounts reject expired fallback no_history sparse_history partial_goals conflict unreachable real].freeze
      SPLITS = { "development" => [ 113, 127 ], "validation" => [ 223, 227 ], "holdout" => [ 331, 347 ] }.freeze
      SIZES = [ 10, 50, 100, 1000 ].freeze
      METRICS = %w[failure_rate_pct fallback_rate_pct average_latency_sec count_absolute_deviation_pp volume_absolute_deviation_pp turnover_gap_pct commission_pct capacity_pressure_pct rpm_pressure_pct unallocated_operations rejected_rate_pct expired_rate_pct runtime_sec retained_bytes].freeze
      OBJECTIVES = METRICS.take(10).freeze
      EXTRA = {
        "distribution" => { "count_share" => 4, "volume_share" => 4, "conversion" => 2, "load_safe" => 2, "intensity" => 1, "turnover_commitment" => 2, "latency" => 0.5, "economy" => 0.25 },
        "equal_goals" => { "count_share" => 1, "volume_share" => 1, "conversion" => 1, "load_safe" => 1, "intensity" => 1, "turnover_commitment" => 1, "latency" => 1, "economy" => 1 },
        "count_latency" => { "count_share" => 2, "volume_share" => 2, "conversion" => 1, "latency" => 1 },
        "latency_only" => { "latency" => 1 }
      }.freeze

      def initialize
        @base = Input::Loader.config_file(File.join(ROOT, "config/routing/final.yml"))
        @candidates = StrategyCatalog.all.transform_values { |v| v.slice("weights", "policy_priorities") }
        @candidates["balanced"] = Configuration.copy(@base.fetch("presets").fetch("balanced"))
        EXTRA.each { |name, weights| @candidates[name] = { "weights" => weights, "policy_priorities" => weights.keys } }
        @rows, @scenarios, @auto_choices = [], [], {}
      end

      def protocol
        { "version" => "paired-final-v1", "splits" => SPLITS, "sizes" => SIZES, "families" => FAMILIES,
          "candidates" => @candidates, "outcomes" => "SHA256(seed, operation_id, provider, channel); cascade position excluded; same immutable inputs, simulator profiles and seed",
          "selection" => "No scalar score. Disqualify any audit violation. Lexicographic: worst failure regret, mean failure, worst fallback regret, mean fallback, worst count regret, mean count error, mean volume error, mean turnover gap, mean latency, mean commission. Each coordinate compared only with its own units; no metric weights. Ties by name.",
          "priority_basis" => "Specification mandates constraints/cascade and explicit soft priorities but gives no outcome utility weights. Reliability and worst-case loss are the user's stated priorities; ordering of remaining goals is a declared engineering choice, not contest points.",
          "regret" => "Per metric: candidate loss minus best feasible candidate loss on the same scenario; missing objectives excluded, explicit zero included. No sums across units.",
          "aggregation" => "Equal scenario macro weights; nearest-rank p90/p95; population SD; missing values omitted with n reported; no queue-length weighting. Public diagnostic excluded from selection.",
          "auto" => "Offline probe only: select one of seven existing strategies on development rows of each family; freeze choices before validation; no holdout tuning. Deployment cost and unseen-family behavior not established.",
          "commission" => "Estimated approved amount * provider_margin_pct /100; aggregate divided by total queued amount; real fee contract not supplied.",
          "turnover" => "Mean relative min deficit or max excess over explicitly supplied bounds (denominator max(bound,1)); absent bounds null; explicit 0 remains a bound.",
          "resources" => "Runner wall time and reachable decisions/report/manifest object bytes per run; process peak RSS measured separately, not attributed to individual candidates.",
          "limitations" => [ "Synthetic scenarios are not a probability model of final traffic", "Finite sample cannot prove mathematical optimality", "Shared generator, IDs and seed blocks correlate scenarios; no IID sampling or significance guarantee", "Count targets required by input schema; optional volume/turnover can be incomplete", "Commission is an estimate; capacity is end-state pressure, not asynchronous production load", "Resource timings are observational and excluded from deterministic fingerprint" ] }
      end

      def call(path:)
        File.write(path, DuoRoute.pretty_json({ "status" => "protocol_frozen", "methodology" => protocol }))
        SPLITS.each do |split, seeds|
          FAMILIES.each_with_index do |family, index|
            seeds.each_with_index do |seed, j|
              size = SIZES[(index + j) % SIZES.length]
              evaluate(split, family, size, seed)
            end
          end
          evaluate(split, "normal", 10_000, seeds.first + 1000)
          if split == "development"
            @auto_choices = @rows.group_by { |r| r["family"] }.transform_values do |rows|
              eligible = rows.select { |r| StrategyCatalog.all.key?(r["candidate"]) }
              summarize(eligible).min_by { |name, value| selection_key(value) + [ name ] }.first
            end
          end
          append_auto(split)
          if split == "validation"
            summary = summarize(@rows.select { |r| r["split"] == split })
            # Auto is a diagnostic, not an eligible deployment candidate.
            @selected = summary.reject { |name, _| name == "auto_probe" }.min_by { |name, value| selection_key(value) + [ name ] }.first
            @locked = { "candidate" => @selected, "validation_ranking" => summary.sort_by { |name, value| selection_key(value) + [ name ] }.map(&:first), "auto_choices" => @auto_choices }
            File.write(path, DuoRoute.pretty_json({ "status" => "selection_locked_before_holdout", "methodology" => protocol, "decision" => @locked }))
          end
        end
        [ 17, 42, 101, 309 ].each { |seed| evaluate("diagnostic", "public", 10, seed) }
        aggregates = @rows.group_by { |r| r["split"] }.transform_values { |rows| summarize(rows) }
        { "status" => "complete", "methodology" => protocol, "inputs" => input_versions,
          "decision" => @locked.merge("holdout_selection_key" => selection_key(aggregates["holdout"][@selected]), "holdout_balanced_key" => selection_key(aggregates["holdout"]["balanced"])),
          "scenario_count" => @scenarios.length, "runner_count" => @rows.count { |r| r["candidate"] != "auto_probe" },
          "scenarios" => @scenarios, "aggregates" => aggregates, "results" => @rows,
          "deterministic_sha256" => digest(@rows.map { |r| r.reject { |k, _| %w[runtime_sec retained_bytes].include?(k) } }) }
      end

      def bundle(family, size, seed)
        generated = Generators::Scenario.new(name: "normal", operations: size, providers: 4, seed:).call
        generated["history"] = generated["history"].map { |r| %w[operation_id created_at amount bank card_brand payment_system status latency_sec].zip(r).to_h }
        if %w[real public].include?(family)
          generated["providers"] = Input::Loader.json_file(File.join(ROOT, "data/providers.json"))
          generated["history"] = Input::Loader.csv_file(File.join(ROOT, "data/operations_history.csv"))
          generated["operations"] = Input::Loader.json_file(File.join(ROOT, "data/operations_queue_10.json")) if family == "public"
          return generated
        end
        ps = generated["providers"]["providers"][0...-1]
        ops = generated["operations"]
        random = Random.new(seed + 919)
        ops.each_with_index do |op, i|
          op["amount"] = random.rand(500..1500) if family == "small"
          op["amount"] = i % 20 == 0 ? 190_000 : 500 if family == "whale"
          op["bank"] = i % 10 == 0 ? "alfa" : "sberbank" if family == "skewed"
          op["created_at"] = (Time.iso8601(generated["providers"]["snapshot_at"]) + i / 20).iso8601 if %w[burst rpm].include?(family)
          op["amount"] = [ 499, 500, 200_000, 200_001 ][i % 4] if family == "amounts"
        end
        ps.each_with_index do |p, i|
          p["daily_approved_amount"] = 9_950_000 if family == "daily"
          p["requests_per_minute_limit"] = 2 + i if family == "rpm"
          p["in_progress_count"] = p["in_progress_count_limit"] if family == "progress" && i.even?
          p["in_progress_amount"] = 950_000 if family == "progress" && i.odd?
          p["status"] = "paused" if family == "unavailable" && i.even?
          p["available_requisites"] = 0 if family == "requisites" && i < 3
          p["banks"] = [ "sberbank", "alfa" ].take(i.even? ? 1 : 2) if family == "banks"
          p["exclude_banks"] = i.odd? if family == "banks"
          p["available_requisites"] = 0 if family == "fallback"
          p.delete("volume_share_pct") if family == "partial_goals" && i != 0
          p["volume_share_pct"] = 0 if family == "partial_goals" && i == 0
          if family == "conflict"
            p["traffic_percentage"] = [ 70, 10, 10, 10 ][i]
            p["volume_share_pct"] = [ 10, 10, 10, 70 ][i]
            p["daily_turnover_min"] = i == 1 ? 2_000_000 : nil
            p["daily_turnover_max"] = i == 0 ? 100_000 : nil
          end
          p["daily_turnover_min"] = 20_000_000 if family == "unreachable"
          p["conversion_24h"] = 0.2 + i * 0.1 if %w[reject expired].include?(family)
        end
        generated["history"] = [] if %w[no_history reject expired].include?(family)
        generated["history"] = generated["history"].take(3) if family == "sparse_history"
        generated
      end

      def run(bundle, candidate, seed, family, audit_level: "compact")
        config = Configuration.copy(@base)
        config["presets"][candidate] = @candidates.fetch(candidate)
        config["simulation"]["failure_expired_share"] = family == "expired" ? 0.95 : 0.05 if %w[expired reject].include?(family)
        Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], history: bundle["history"], config:, seed:, preset: candidate, audit_level:).call
      end

      def evaluate(split, family, size, seed)
        data = bundle(family, size, seed)
        id = "#{split}/#{family}/#{size}/#{seed}"
        hashes = %w[providers operations history].to_h { |k| [ k, digest(data[k]) ] }
        @scenarios << { "id" => id, "split" => split, "family" => family, "size" => size, "seed" => seed, "input_sha256" => hashes }
        @candidates.keys.each do |candidate|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = run(data, candidate, seed, family)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          audit = SubmissionAudit.new(providers: data["providers"], operations: data["operations"], decisions: result.decisions, report: result.report, config: result.manifest["resolved_configuration"])
          audit.call
          @rows << metrics(data, result).merge("scenario" => id, "split" => split, "family" => family, "size" => size, "seed" => seed, "candidate" => candidate,
            "runtime_sec" => elapsed, "retained_bytes" => retained_bytes(result), "hard_violations" => 0, "audit_checks" => audit.checks,
            "decisions_sha256" => digest(result.decisions))
        end
        raise "input mutation" unless hashes == %w[providers operations history].to_h { |k| [ k, digest(data[k]) ] }
        warn "#{id}: #{@rows.length} rows"
      end

      def metrics(data, result)
        report = result.report
        ps = data["providers"]["providers"].to_h { |p| [ p["payment_system"], p ] }
        amounts = data["operations"].to_h { |op| [ op["operation_id"], op["amount"] ] }
        fees = result.decisions.sum do |d|
          d["simulated_result"] == "approved" ? amounts.fetch(d["operation_id"]).to_f * ps.fetch(d["selected_provider"])["provider_margin_pct"].to_f / 100 : 0
        end
        gaps = report["turnover_commitments"].values.flat_map do |v|
          [ v["minimum"].nil? ? nil : [ (v["minimum"] - v["actual"]).to_f / [ v["minimum"], 1 ].max * 100, 0 ].max,
            v["maximum"].nil? ? nil : [ (v["actual"] - v["maximum"]).to_f / [ v["maximum"], 1 ].max * 100, 0 ].max ].compact
        end
        capacities = report["capacity_utilization"].values
        { "approval_rate_pct" => report["approval_rate_pct"], "failure_rate_pct" => 100 - report["approval_rate_pct"],
          "fallback_rate_pct" => report["fallback_rate_pct"], "average_latency_sec" => report["average_latency_sec"],
          "turnover_gap_pct" => mean(gaps), "commission_amount" => fees, "commission_pct" => fees / amounts.values.sum * 100,
          "capacity_pressure_pct" => capacities.flat_map { |v| v.values_at("daily_utilization_pct", "in_progress_count_utilization_pct", "in_progress_amount_utilization_pct") }.compact.max,
          "rpm_pressure_pct" => capacities.filter_map { |v| v["requests_last_minute"].fdiv(v["rpm_limit"]) * 100 if v["rpm_limit"]&.positive? }.max,
          "unallocated_operations" => result.decisions.count { |d| d["attempts"].none? { |a| a.key?("result") } },
          "rejected_rate_pct" => report["results"].fetch("rejected", 0).fdiv(result.decisions.size) * 100,
          "expired_rate_pct" => report["results"].fetch("expired", 0).fdiv(result.decisions.size) * 100 }.merge(Reporting::ComparisonMetrics.call(report))
      end

      def append_auto(split)
        @rows.select { |r| r["split"] == split && r["candidate"] == @auto_choices[r["family"]] }.each do |row|
          @rows << row.merge("candidate" => "auto_probe", "selected_strategy" => row["candidate"], "runtime_sec" => row["runtime_sec"], "selector_cost_included" => false)
        end
      end

      def summarize(rows)
        paired = rows.group_by { |r| r["scenario"] }
        rows.group_by { |r| r["candidate"] }.transform_values do |group|
          stats = METRICS.to_h { |metric| [ metric, statistics(group.filter_map { |r| r[metric] }) ] }
          regrets = OBJECTIVES.to_h do |metric|
            values = group.filter_map do |r|
              next if r[metric].nil?
              r[metric] - paired[r["scenario"]].filter_map { |p| p[metric] }.min
            end
            [ metric, statistics(values) ]
          end
          comparisons = METRICS.to_h do |metric|
            deltas = group.filter_map do |r|
              baseline = paired[r["scenario"]].find { |p| p["candidate"] == "balanced" }
              r[metric] - baseline[metric] if baseline && !r[metric].nil? && !baseline[metric].nil?
            end
            wins, losses = deltas.select { |v| v < -1e-9 }, deltas.select { |v| v > 1e-9 }
            [ metric, { "wins" => wins.size, "ties" => deltas.size - wins.size - losses.size, "losses" => losses.size,
              "mean_gain" => mean(wins.map(&:-@)), "mean_loss" => mean(losses), "max_loss" => losses.max } ]
          end
          front = group.count do |r|
            !paired[r["scenario"]].any? do |other|
              active = OBJECTIVES.select { |m| !r[m].nil? && !other[m].nil? }
              active.all? { |m| other[m] <= r[m] + 1e-9 } && active.any? { |m| other[m] < r[m] - 1e-9 }
            end
          end
          { "metrics" => stats, "regret" => regrets, "paired_vs_balanced" => comparisons, "pareto_count" => front,
            "scenario_count" => group.size, "hard_violations" => group.sum { |r| r["hard_violations"] } }
        end
      end

      def selection_key(summary)
        m, r = summary.values_at("metrics", "regret")
        [ summary["hard_violations"].positive? ? 1 : 0, r["failure_rate_pct"]["worst"], m["failure_rate_pct"]["mean"],
          r["fallback_rate_pct"]["worst"], m["fallback_rate_pct"]["mean"], r["count_absolute_deviation_pp"]["worst"],
          m["count_absolute_deviation_pp"]["mean"], m["volume_absolute_deviation_pp"]["mean"], m["turnover_gap_pct"]["mean"],
          m["average_latency_sec"]["mean"], m["commission_pct"]["mean"] ].compact.map { |v| v.round(8) }
      end

      def statistics(values)
        return { "n" => 0 } if values.empty?
        sorted = values.sort
        avg = mean(values)
        { "n" => values.length, "mean" => avg, "median" => (sorted[(values.size - 1) / 2] + sorted[values.size / 2]) / 2.0,
          "p90" => sorted[(values.size * 0.9).ceil - 1], "p95" => sorted[(values.size * 0.95).ceil - 1],
          "best" => sorted.first, "worst" => sorted.last, "sd" => Math.sqrt(mean(values.map { |v| (v - avg)**2 })) }
      end

      def retained_bytes(result)
        seen = {}
        visit = lambda do |object|
          return 0 if seen[object.object_id]
          seen[object.object_id] = true
          bytes = ObjectSpace.memsize_of(object)
          case object
          when Hash then object.each { |k, v| bytes += visit.call(k) + visit.call(v) }
          when Array then object.each { |v| bytes += visit.call(v) }
          end
          bytes
        end
        visit.call([ result.decisions, result.report, result.manifest ])
      end

      def input_versions
        paths = %w[data/providers.json data/operations_queue_10.json data/operations_history.csv config/routing/final.yml lib/duo_route/evaluation/final_study.rb lib/duo_route/simulation/seeded.rb lib/duo_route/scorer.rb]
        paths.to_h { |p| [ p, Digest::SHA256.file(File.join(ROOT, p)).hexdigest ] }
      end

      def mean(values) = values.empty? ? nil : values.sum.fdiv(values.size)
      def digest(value) = Digest::SHA256.hexdigest(DuoRoute.pretty_json(value))
    end
  end
end
