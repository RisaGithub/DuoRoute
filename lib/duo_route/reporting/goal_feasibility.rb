# frozen_string_literal: true

module DuoRoute
  module Reporting
    # Post hoc only. Eligibility is measured on the realized path, not on alternative allocations.
    class GoalFeasibility
      def self.call(providers:, operations:, decisions:, fallback: "spacepayments")
        amounts = operations.to_h { |op| [ op["operation_id"], op["amount"] ] }
        total = decisions.size
        providers.reject { |p| [ fallback, "spacepayments" ].include?(p["payment_system"]) }.to_h do |provider|
          name = provider["payment_system"]
          eligible = decisions.select { |row| row["eligible_pool"].include?(name) }
          failures = decisions.flat_map { |row| row.dig("constraint_matrix", name, "failures") || [] }.map { |failure| failure["code"] }.tally
          actual_count = decisions.count { |row| row["selected_provider"] == name }
          target = provider["traffic_percentage"].to_f
          upper = total.zero? ? 0.0 : eligible.size.fdiv(total) * 100
          actual = total.zero? ? 0.0 : actual_count.fdiv(total) * 100
          status = if (actual - target).abs < 1e-9 then "achieved" elsif upper < target then "not_reachable_on_observed_path" else "not_ruled_out" end
          explanation = case status
          when "achieved" then "Фактическая доля совпала с целью."
          when "not_reachable_on_observed_path" then "Допуск только для #{eligible.size}/#{total} операций (#{upper.round(2)}%) ниже цели #{target}%. Ограничения: #{failures.keys.join(', ')}."
          else "Наблюдаемый допуск не исключает цель; отклонение связано с ответами провайдеров, конкурирующими целями и дискретностью очереди. Совместная достижимость не доказана."
          end
          [ name, { "target_count_share_pct" => target, "actual_count_share_pct" => actual.round(2),
            "eligible_operations" => eligible.size, "eligible_amount" => Money.number(Money.sum(eligible.map { |row| amounts.fetch(row["operation_id"]) })),
            "blocking_constraints" => failures.sort_by { |code, count| [ -count, code ] }.to_h,
            "observed_upper_share_pct" => upper.round(2), "status" => status,
            "target_reachable_on_observed_path" => status == "achieved" ? true : (status == "not_reachable_on_observed_path" ? false : nil),
            "explanation" => explanation, "bound_scope" => "Observed eligibility, not a mathematical maximum over counterfactual routes." } ]
        end
      end
    end
  end
end
