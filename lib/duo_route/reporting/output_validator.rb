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
          %w[operation_id selected_provider attempts simulated_result latency_sec].each do |field|
            issues << ValidationIssue.new(path: "#{path}.#{field}", code: "required", message: "обязательное поле отсутствует") unless decision.key?(field)
          end
          unless %w[approved rejected expired].include?(decision["simulated_result"])
            issues << ValidationIssue.new(path: "#{path}.simulated_result", code: "invalid_enum", message: "недопустимый результат")
          end
          Array(decision["attempts"]).each_with_index do |attempt, attempt_index|
            %w[provider decision reason].each do |field|
              issues << ValidationIssue.new(path: "#{path}.attempts[#{attempt_index}].#{field}", code: "required", message: "обязательное поле отсутствует") unless attempt.key?(field)
            end
            unless %w[selected skipped].include?(attempt["decision"])
              issues << ValidationIssue.new(path: "#{path}.attempts[#{attempt_index}].decision", code: "invalid_enum", message: "ожидается selected или skipped")
            end
          end
          selected = Array(decision["attempts"]).select { |attempt| attempt["decision"] == "selected" }
          issues << ValidationIssue.new(path: "#{path}.attempts", code: "selected_count", message: "должна быть ровно одна selected попытка") unless selected.length == 1
          if selected.one? && selected.first["provider"] != decision["selected_provider"]
            issues << ValidationIssue.new(path: path, code: "selected_mismatch", message: "selected_provider не совпадает с selected attempt")
          end
        end
        if operation_ids && value.map { |item| item["operation_id"] }.sort != operation_ids.sort
          issues << ValidationIssue.new(path: "$", code: "coverage_mismatch", message: "набор operation_id не совпадает с очередью")
        end
        issues
      end

      def report(value, expected_total: nil)
        issues = []
        %w[period total_operations distribution volume_distribution results recommendations recommendation_details reproducibility].each do |field|
          issues << ValidationIssue.new(path: "$.#{field}", code: "required", message: "обязательное поле отсутствует") unless value.is_a?(Hash) && value.key?(field)
        end
        if expected_total && value["total_operations"] != expected_total
          issues << ValidationIssue.new(path: "$.total_operations", code: "wrong_total", message: "ожидалось #{expected_total}")
        end
        issues
      end
    end
  end
end
