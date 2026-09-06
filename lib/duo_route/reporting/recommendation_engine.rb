# frozen_string_literal: true

module DuoRoute
  module Reporting
    class RecommendationEngine
      def initialize(distribution:, volume_distribution:, utilization:, provider_performance:, turnover:)
        @distribution = distribution
        @volume_distribution = volume_distribution
        @utilization = utilization
        @provider_performance = provider_performance
        @turnover = turnover
      end

      def call
        details = []
        @utilization.each do |provider, metrics|
          next unless metrics["daily_utilization_pct"] && metrics["daily_utilization_pct"] >= 90
          details << detail("warning", provider, "daily utilization #{metrics['daily_utilization_pct']}%",
            "traffic_percentage", @distribution.dig(provider, "target_pct"), "снизить вес/долю или поднять лимит после согласования",
            "при текущем запасе новые операции могут перейти в fallback")
        end
        @distribution.each do |provider, row|
          if provider == "spacepayments"
            if row["count"].positive?
              details << detail("info", provider, "fallback: #{row['count']} операций / #{row['share_pct']}%",
                "fallback_rate_pct", row["share_pct"],
                "снижать частоту fallback через устранение причин недоступности внешних провайдеров; проверить timeout, reject и отсутствие допустимого внешнего провайдера",
                "резервный провайдер используется после исчерпания допустимых внешних вариантов и не участвует в обычном ranking")
            end
            next
          end
          next unless row["deviation_pp"].abs >= 15 && row["count"] >= 1
          action = row["deviation_pp"].positive? ? "снизить count_share/проверить недоступность альтернатив" : "повысить count_share или устранить hard-исключения"
          details << detail("info", provider, "count deviation #{row['deviation_pp']} п.п.", "traffic_percentage",
            row["target_pct"], action, "фактическая доля #{row['share_pct']}% заметно отличается от цели")
        end
        @provider_performance.each do |provider, row|
          next unless row["attempts"] >= 3 && row["success_rate_pct"] < 60
          details << detail("warning", provider, "success #{row['success_rate_pct']}% на #{row['attempts']} попытках",
            "conversion weight", row["success_rate_pct"], "понизить effective conversion до проверки канала",
            "наблюдаемая успешность ниже 60%")
        end
        @turnover.each do |provider, row|
          next unless row["minimum"] && row["actual"] < row["minimum"]
          next if row["provider_status"] && row["provider_status"] != "active"
          next if row["hard_limit"] && row["minimum"] > row["hard_limit"]
          details << detail("info", provider, "дефицит #{(row['minimum'] - row['actual']).round(2)}",
            "daily_turnover_min", row["minimum"], "увеличить turnover_commitment weight", "минимальный оборот пока не достигнут")
        end
        details.uniq { |item| [ item["provider"], item["rule_parameter"], item["evidence"] ] }
      end

      private

      def detail(severity, provider, evidence, rule, current, action, rationale)
        { "severity" => severity, "provider" => provider, "evidence" => evidence, "rule_parameter" => rule,
          "current_value" => current, "proposed_action" => action, "rationale" => rationale }
      end
    end
  end
end
