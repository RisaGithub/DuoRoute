# frozen_string_literal: true

module DuoRoute
  module Reporting
    class OutputValidator
      def decisions(value, operation_ids: nil)
        issues = []
        unless value.is_a?(Array)
          return [ ValidationIssue.new(path: "$", code: "wrong_type", message: "decisions должен быть массивом") ]
        end
        value.each_with_index do |decision, index|
          path = "$[#{index}]"
          unless decision.is_a?(Hash)
            issues << issue(path, "wrong_type", "решение должно быть объектом")
            next
          end
          issues << issue("#{path}.latency_sec", "invalid_latency", "ожидается конечное неотрицательное число") unless nonnegative?(decision["latency_sec"])
          unless decision["attempts"].is_a?(Array) && decision["attempts"].all? { |attempt| attempt.is_a?(Hash) }
            issues << issue("#{path}.attempts", "wrong_type", "ожидается массив объектов")
            next
          end
          attempts = decision["attempts"]
          names = attempts.map { |attempt| attempt["provider"] }
          issues << issue("#{path}.attempts", "duplicate_attempt", "повтор провайдера") unless names == names.uniq
          invoked = attempts.select { |attempt| attempt.key?("result") }
          if invoked.all? { |attempt| nonnegative?(attempt["latency_sec"]) }
            actual = invoked.sum { |attempt| attempt["latency_sec"] }
            issues << issue(path, "latency_mismatch", "latency не равна сумме попыток") unless actual == decision["latency_sec"]
          else
            issues << issue(path, "invalid_latency", "неверная latency попытки")
          end
          if decision["constraint_matrix"]
            invoked.each do |attempt|
              evaluation = decision["constraint_matrix"][attempt["provider"]]
              unless evaluation && evaluation["eligible"] && evaluation["checks"].all? { |check| check["eligible"] }
                issues << issue(path, "hard_constraint_violation", "вызван недопустимый провайдер #{attempt['provider']}")
              end
            end
          end
          if decision["fallback_used"] && decision["eligible_pool"]
            untried = decision["eligible_pool"] - invoked.map { |attempt| attempt["provider"] }
            issues << issue(path, "early_fallback", "допустимые внешние провайдеры не вызваны") if untried.any?
          end
          %w[operation_id selected_provider attempts simulated_result latency_sec].each do |field|
            issues << ValidationIssue.new(path: "#{path}.#{field}", code: "required", message: "обязательное поле отсутствует") unless decision.key?(field)
          end
          unless %w[approved rejected expired].include?(decision["simulated_result"])
            issues << ValidationIssue.new(path: "#{path}.simulated_result", code: "invalid_enum", message: "недопустимый результат")
          end
          Array(decision["attempts"]).each_with_index do |attempt, attempt_index|
            issues << issue(path, "unknown_reason", "неизвестный reason code") unless ReasonCodes::ALL.include?(attempt["reason"])
            issues << issue(path, "invalid_result", "неверный результат попытки") if attempt.key?("result") && !%w[approved rejected expired].include?(attempt["result"])
            %w[provider decision reason].each do |field|
              issues << ValidationIssue.new(path: "#{path}.attempts[#{attempt_index}].#{field}", code: "required", message: "обязательное поле отсутствует") unless attempt.key?(field)
            end
            unless %w[selected skipped].include?(attempt["decision"])
              issues << ValidationIssue.new(path: "#{path}.attempts[#{attempt_index}].decision", code: "invalid_enum", message: "ожидается selected или skipped")
            end
          end
          selected = Array(decision["attempts"]).select { |attempt| attempt["decision"] == "selected" }
          issues << ValidationIssue.new(path: "#{path}.attempts", code: "selected_count", message: "должна быть ровно одна selected попытка") unless selected.length == 1
          if selected.one? && selected.first["result"] != decision["simulated_result"]
            issues << issue(path, "result_mismatch", "результат решения не совпадает с selected attempt")
          end
          if selected.one? && selected.first["provider"] != decision["selected_provider"]
            issues << ValidationIssue.new(path: path, code: "selected_mismatch", message: "selected_provider не совпадает с selected attempt")
          end
        end
        if operation_ids && value.filter_map { |item| item["operation_id"] if item.is_a?(Hash) }.sort != operation_ids.sort
          issues << ValidationIssue.new(path: "$", code: "coverage_mismatch", message: "набор operation_id не совпадает с очередью")
        end
        issues.concat(finite_values(value))
        issues
      end

      def report(value, expected_total: nil)
        issues = []
        %w[period total_operations distribution volume_distribution results skip_reasons projected_daily_utilization recommendations recommendation_details reproducibility].each do |field|
          issues << ValidationIssue.new(path: "$.#{field}", code: "required", message: "обязательное поле отсутствует") unless value.is_a?(Hash) && value.key?(field)
        end
        return issues unless value.is_a?(Hash)
        if expected_total && value["total_operations"] != expected_total
          issues << ValidationIssue.new(path: "$.total_operations", code: "wrong_total", message: "ожидалось #{expected_total}")
        end
        if value["distribution"].is_a?(Hash) && value["results"].is_a?(Hash)
          issues << issue("$report", "count_mismatch", "сумма распределения/результатов не равна total") unless value["distribution"].values.sum { |row| row["count"].to_i } == value["total_operations"] && value["results"].values.sum == value["total_operations"]
        end
        issues.concat(finite_values(value))
        issues
      end

      def consistency(result, operations:, providers:)
        issues = []
        names = providers.map { |provider| provider["payment_system"] }
        ordered = operations.each_with_index.sort_by { |operation, index| [ Time.iso8601(operation["created_at"]), index ] }.map(&:first)
        issues << issue("$decisions", "order_mismatch", "порядок решений не соответствует времени очереди") unless result.decisions.map { |row| row["operation_id"] } == ordered.map { |row| row["operation_id"] }
        amounts = Hash.new(BigDecimal("0"))
        counts = Hash.new(0)
        result.decisions.zip(ordered).each do |decision, operation|
          name = decision["selected_provider"]
          issues << issue("$decisions", "unknown_provider", "провайдер отсутствует в snapshot") unless names.include?(name)
          counts[name] += 1
          amounts[name] += Money.decimal(operation["amount"])
        end
        total_amount = amounts.values.sum
        providers.each do |provider|
          name = provider["payment_system"]
          expected_count_share = percentage(counts[name], operations.length)
          expected_volume_share = percentage(amounts[name], total_amount)
          expected = {
            "distribution" => { "share_pct" => expected_count_share, "target_pct" => provider["traffic_percentage"], "deviation_pp" => (expected_count_share - provider["traffic_percentage"]).round(2) },
            "volume_distribution" => { "share_pct" => expected_volume_share, "target_pct" => provider["volume_share_pct"], "deviation_pp" => provider["volume_share_pct"] && (expected_volume_share - provider["volume_share_pct"]).round(2) }
          }
          expected.each do |section, fields|
            fields.each do |field, value|
              issues << issue("$report.#{section}.#{name}.#{field}", "percentage_mismatch", "поле не согласовано с исходными данными") unless result.report.dig(section, name, field) == value
            end
          end
          issues << issue("$report.distribution.#{name}", "count_mismatch", "count не совпадает с decisions") unless result.report.dig("distribution", name, "count") == counts[name]
          issues << issue("$report.volume_distribution.#{name}", "amount_mismatch", "сумма не совпадает с operations") unless Money.decimal(result.report.dig("volume_distribution", name, "amount")) == amounts[name]
        end
        expected_results = result.decisions.map { |row| row["simulated_result"] }.tally
        expected_skips = result.decisions.flat_map { |row| row["attempts"] }.select { |row| row["decision"] == "skipped" }.map { |row| row["reason"] }.tally
        expected_summary = { "results" => expected_results, "skip_reasons" => expected_skips,
          "approval_rate_pct" => percentage(expected_results.fetch("approved", 0), operations.length),
          "fallback_rate_pct" => percentage(result.decisions.count { |row| row["fallback_used"] }, operations.length),
          "average_latency_sec" => (result.decisions.sum { |row| row["latency_sec"] }.fdiv(operations.length)).round(2) }
        expected_summary.each do |field, value|
          issues << issue("$report.#{field}", "summary_mismatch", "поле не согласовано с decisions") unless result.report[field] == value
        end
        issues << issue("$report.total_amount", "amount_mismatch", "total_amount не совпадает с operations") unless Money.decimal(result.report["total_amount"]) == amounts.values.sum
        issues
      end

      private

      def percentage(value, total) = total.zero? ? 0.0 : (value.to_f / total * 100).round(2)
      def nonnegative?(value) = value.is_a?(Numeric) && value.finite? && value >= 0
      def issue(path, code, message) = ValidationIssue.new(path:, code:, message:)

      def finite_values(value, path = "$")
        case value
        when Hash then value.flat_map { |key, item| finite_values(item, "#{path}.#{key}") }
        when Array then value.flat_map.with_index { |item, index| finite_values(item, "#{path}[#{index}]") }
        when Numeric then value.finite? ? [] : [ issue(path, "nonfinite_number", "NaN/Infinity запрещены") ]
        else []
        end
      end
    end
  end
end
