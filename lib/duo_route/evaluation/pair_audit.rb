# frozen_string_literal: true

module DuoRoute
  module Evaluation
    # Independent comparison contract, in addition to the standalone state replay.
    module PairAudit
      module_function

      def call(results)
        reference = results.first.manifest
        common = %w[providers_sha256 operations_sha256 history_sha256 outcomes_sha256 seed random_scenario simulation]
        observed = {}
        results.each do |result|
          raise Error, "unpaired inputs or simulation" unless common.all? { |key| result.manifest[key] == reference[key] }
          shared_config = %w[routing provider_overrides calibration simulation]
          unless shared_config.all? { |key| result.manifest.dig("resolved_configuration", key) == reference.dig("resolved_configuration", key) }
            raise Error, "unpaired constraints or goals"
          end
          result.decisions.each do |decision|
            decision["attempts"].each do |attempt|
              next unless attempt.key?("result")
              key = [ decision["operation_id"], attempt["provider"] ]
              value = attempt.slice("result", "latency_sec", "status_check_result")
              raise Error, "cascade-dependent outcome" if observed.key?(key) && observed[key] != value
              observed[key] = value
            end
          end
          %w[distribution volume_distribution].each do |metric|
            targets = result.report.fetch(metric).transform_values { |row| row["target_pct"] }
            expected_targets = results.first.report.fetch(metric).transform_values { |row| row["target_pct"] }
            raise Error, "unpaired targets" unless targets == expected_targets
            result.report.fetch(metric).each_value do |row|
              expected = row["target_pct"].nil? ? nil : (row["share_pct"] - row["target_pct"]).round(2)
              raise Error, "missing/zero target mutation" unless row["deviation_pp"] == expected
            end
          end
        end
        true
      end
    end
  end
end
