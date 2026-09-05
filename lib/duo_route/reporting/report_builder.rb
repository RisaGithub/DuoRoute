# frozen_string_literal: true

module DuoRoute
  module Reporting
    class ReportBuilder
      def initialize(providers_data:, operations:, decisions:, state:, history:, manifest:)
        @providers_data = providers_data
        @providers = providers_data.fetch("providers")
        @operations = operations
        @operations_by_id = operations.to_h { |operation| [ operation["operation_id"], operation ] }
        @decisions = decisions
        @state = state
        @history = history
        @manifest = manifest
      end

      def call
        distribution = count_distribution
        volumes = volume_distribution
        utilization = provider_utilization
        performance = provider_performance
        turnover = turnover_status
        recommendation_details = RecommendationEngine.new(distribution:, volume_distribution: volumes,
          utilization:, provider_performance: performance, turnover:).call
        {
          "schema_version" => SCHEMA_VERSION,
          "period" => period,
          "total_operations" => @operations.length,
          "total_amount" => number(@operations.sum { |operation| operation["amount"] }),
          "distribution" => distribution,
          "volume_distribution" => volumes,
          "results" => @decisions.map { |decision| decision["simulated_result"] }.tally,
          "approval_rate_pct" => percentage(@decisions.count { |decision| decision["simulated_result"] == "approved" }, @decisions.length),
          "fallback_rate_pct" => percentage(@decisions.count { |decision| decision["fallback_used"] }, @decisions.length),
          "average_latency_sec" => average(@decisions.map { |decision| decision["latency_sec"] }),
          "skip_reasons" => skip_reasons,
          "provider_performance" => performance,
          "projected_daily_utilization" => utilization.transform_values { |row| row.slice("daily_used", "daily_limit", "daily_utilization_pct") },
          "capacity_utilization" => utilization,
          "turnover_commitments" => turnover,
          "target_exceptions" => target_exceptions(distribution, volumes),
          "history_analytics" => HistoryAnalyzer.new(@history).call,
          "recommendations" => recommendation_details.map { |item| "#{item['provider']}: #{item['proposed_action']} (#{item['evidence']})" },
          "recommendation_details" => recommendation_details,
          "reproducibility" => @manifest
        }
      end

      private

      def count_distribution
        @providers.to_h do |provider|
          name = provider["payment_system"]
          count = @decisions.count { |decision| decision["selected_provider"] == name }
          share = percentage(count, @decisions.length)
          target = provider["traffic_percentage"].to_f
          [ name, { "count" => count, "share_pct" => share, "target_pct" => target, "deviation_pp" => (share - target).round(2) } ]
        end
      end

      def volume_distribution
        total = @operations.sum { |operation| operation["amount"] }.to_f
        amounts = Hash.new(0.0)
        @decisions.each do |decision|
          operation = @operations_by_id.fetch(decision["operation_id"])
          amounts[decision["selected_provider"]] += operation["amount"]
        end
        @providers.to_h do |provider|
          name = provider["payment_system"]
          share = percentage(amounts[name], total)
          target = provider["volume_share_pct"]
          [ name, { "amount" => number(amounts[name]), "share_pct" => share, "target_pct" => target,
            "deviation_pp" => target.nil? ? nil : (share - target).round(2) } ]
        end
      end

      def skip_reasons
        @decisions.flat_map { |decision| decision["attempts"] }
          .select { |attempt| attempt["decision"] == "skipped" }
          .map { |attempt| attempt["reason"] }.tally.sort.to_h
      end

      def provider_performance
        @providers.to_h do |provider|
          name = provider["payment_system"]
          invoked = @decisions.flat_map { |decision| decision["attempts"] }.select { |attempt| attempt["provider"] == name && attempt.key?("result") }
          approved = invoked.count { |attempt| attempt["result"] == "approved" }
          [ name, { "attempts" => invoked.length, "approved" => approved,
            "success_rate_pct" => percentage(approved, invoked.length),
            "average_latency_sec" => average(invoked.filter_map { |attempt| attempt["latency_sec"] }),
            "results" => invoked.map { |attempt| attempt["result"] }.tally } ]
        end
      end

      def provider_utilization
        final = @state.snapshot
        @providers.to_h do |provider|
          name = provider["payment_system"]
          state = final.fetch(name)
          [ name, {
            "daily_start" => number(provider["daily_approved_amount"]), "daily_used" => number(state["daily_approved_amount"]),
            "daily_limit" => provider["daily_amount_limit"], "daily_utilization_pct" => util(state["daily_approved_amount"], provider["daily_amount_limit"]),
            "in_progress_count_start" => provider["in_progress_count"], "in_progress_count_end" => state["in_progress_count"],
            "in_progress_count_limit" => provider["in_progress_count_limit"],
            "in_progress_count_utilization_pct" => util(state["in_progress_count"], provider["in_progress_count_limit"]),
            "in_progress_amount_start" => provider["in_progress_amount"], "in_progress_amount_end" => state["in_progress_amount"],
            "in_progress_amount_limit" => provider["in_progress_amount_limit"],
            "in_progress_amount_utilization_pct" => util(state["in_progress_amount"], provider["in_progress_amount_limit"]),
            "requests_last_minute" => state["requests_last_minute"], "rpm_limit" => provider["requests_per_minute_limit"]
          } ]
        end
      end

      def turnover_status
        final = @state.snapshot
        @providers.to_h do |provider|
          actual = final.dig(provider["payment_system"], "daily_approved_amount")
          min = provider["daily_turnover_min"]
          max = provider["daily_turnover_max"]
          status = if min && actual < min then "below_minimum" elsif max && actual > max then "above_maximum" else "within_commitment" end
          [ provider["payment_system"], { "actual" => actual, "minimum" => min, "maximum" => max, "status" => status } ]
        end
      end

      def target_exceptions(distribution, volumes)
        distribution.filter_map do |provider, row|
          next unless row["deviation_pp"].abs >= 10
          blockers = @decisions.flat_map { |decision| decision["attempts"] }.select { |attempt| attempt["provider"] == provider && attempt["decision"] == "skipped" }.map { |attempt| attempt["reason"] }.tally
          { "provider" => provider, "metric" => "count_share", "deviation_pp" => row["deviation_pp"],
            "explanation" => blockers.empty? ? "weighted soft goals selected alternatives" : "hard/fallback events constrained target",
            "evidence" => blockers }
        end + volumes.filter_map do |provider, row|
          next if row["deviation_pp"].nil? || row["deviation_pp"].abs < 10
          { "provider" => provider, "metric" => "volume_share", "deviation_pp" => row["deviation_pp"],
            "explanation" => "online projected scoring cannot guarantee an exact share on a short queue" }
        end
      end

      def period
        times = @operations.map { |operation| Time.iso8601(operation["created_at"]) }
        times.map(&:to_date).min == times.map(&:to_date).max ? times.first.to_date.iso8601 : "#{times.min.iso8601}/#{times.max.iso8601}"
      end

      def percentage(value, total) = total.to_f.zero? ? 0.0 : (value.to_f / total * 100).round(2)
      def average(values) = values.empty? ? 0.0 : (values.sum.to_f / values.length).round(2)
      def util(value, limit) = limit.nil? || limit.to_f.zero? ? nil : percentage(value, limit)
      def number(value) = value.to_f == value.to_i ? value.to_i : value.to_f.round(2)
    end
  end
end
