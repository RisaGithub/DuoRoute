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
            "amount" => rows.sum { |row| row["amount"].to_f }.round(2),
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
          next provider unless stats && stats["operations"] >= minimum_samples
          n = stats["operations"]
          blended = ((provider["conversion_24h"] * prior_strength) + (stats["empirical_conversion"] * n)) / (prior_strength + n)
          provider.merge("effective_conversion" => blended.round(6), "conversion_calibration" => {
            "snapshot" => provider["conversion_24h"], "empirical" => stats["empirical_conversion"], "samples" => n,
            "prior_strength" => prior_strength
          })
        end
      end
    end
  end
end
