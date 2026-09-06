# frozen_string_literal: true

module DuoRoute
  module Reporting
    module ComparisonMetrics
      module_function

      def targets(distribution)
        distribution.select { |_, row| !row["target_pct"].nil? }
      end

      def deviation(distribution)
        rows = targets(distribution).values
        return nil if rows.empty?
        rows.sum { |row| row.fetch("deviation_pp").abs }.round(2)
      end

      def call(report)
        { "count_absolute_deviation_pp" => deviation(report.fetch("distribution")),
          "volume_absolute_deviation_pp" => deviation(report.fetch("volume_distribution")),
          "count_target_providers" => targets(report.fetch("distribution")).keys,
          "volume_target_providers" => targets(report.fetch("volume_distribution")).keys }
      end
    end
  end
end
