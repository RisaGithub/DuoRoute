# frozen_string_literal: true

module DuoRoute
  module Reporting
    class HistoryAnalyzer
      def initialize(rows)
        @rows = rows
      end

      def call
        @rows.group_by { |row| row["payment_system"] }.transform_values do |rows|
          approved = rows.count { |row| row["status"] == "approved" }
          latencies = rows.filter_map { |row| Float(row["latency_sec"], exception: false) }
          {
            "operations" => rows.length,
            "amount" => Money.number(Money.sum(rows.map { |row| row["amount"] })),
            "approved" => approved,
            "empirical_conversion" => rows.empty? ? 0 : (approved.to_f / rows.length).round(6),
            "average_latency_sec" => latencies.empty? ? 0 : (latencies.sum / latencies.length).round(2),
            "result_mix" => rows.map { |row| row["status"] }.tally
          }
        end
      end

      def calibrated(providers, minimum_samples:, prior_strength:)
        analytics = call
        providers.map do |provider|
          stats = analytics[provider["payment_system"]]
          n = stats ? stats["operations"] : 0
          unless n >= minimum_samples
            next provider.merge("conversion_calibration" => { "source" => "provider_snapshot", "snapshot" => provider["conversion_24h"], "samples" => n, "minimum_samples" => minimum_samples, "prior_strength" => prior_strength, "reason" => "history_below_minimum_samples" })
          end
          blended = ((provider["conversion_24h"] * prior_strength) + (stats["empirical_conversion"] * n)) / (prior_strength + n)
          provider.merge("effective_conversion" => blended.round(6), "conversion_calibration" => {
            "source" => "calibrated_history", "minimum_samples" => minimum_samples, "snapshot" => provider["conversion_24h"], "empirical" => stats["empirical_conversion"], "samples" => n,
            "prior_strength" => prior_strength
          })
        end
      end
    end
  end
end
