# frozen_string_literal: true

module DuoRoute
  module Generators
    class Scenario
      NAMES = %w[normal hard_limits fallback conflicting_goals high_load timeouts invalid_data stress].freeze
      BANKS = %w[sberbank alfa tinkoff vtb gazprombank raiffeisen].freeze

      def initialize(name:, operations:, providers:, seed:)
        raise InputError, [ ValidationIssue.new(path: "$scenario", code: "unknown_scenario", message: "допустимы #{NAMES.join(', ')}") ] unless NAMES.include?(name)
        @name = name
        @operation_count = operations.to_i
        @provider_count = providers.to_i
        @random = Random.new(seed.to_i)
        @seed = seed.to_i
      end

      def call
        providers = build_providers
        operations = build_operations
        history = build_history(providers)
        outcomes = build_outcomes(operations, providers)
        corrupt!(providers, operations) if @name == "invalid_data"
        { "providers" => providers, "operations" => operations, "history" => history, "outcomes" => outcomes,
          "manifest" => { "scenario" => @name, "seed" => @seed } }
      end

      private

      def build_providers
        external = Array.new(@provider_count) do |index|
          share = 100.0 / @provider_count
          {
            "payment_system" => "provider_#{index + 1}", "status" => "active", "traffic_percentage" => share.round(6),
            "priority" => index + 1, "limit_amount_min" => 500, "limit_amount_max" => 200_000,
            "daily_amount_limit" => @name == "hard_limits" ? 120_000 : 10_000_000,
            "daily_approved_amount" => @name == "high_load" ? 8_900_000 : 0,
            "in_progress_count_limit" => 10, "in_progress_count" => @name == "high_load" ? 8 : 0,
            "in_progress_amount_limit" => 1_000_000, "in_progress_amount" => 0,
            "available_requisites" => @name == "fallback" ? 0 : 10, "conversion_24h" => (0.72 + index * 0.04).clamp(0, 0.98),
            "avg_latency_sec" => 15 + index * 6, "banks" => [], "exclude_banks" => false,
            "provider_margin_pct" => 0.7 + index * 0.08, "merchant_margin_pct" => 1.5,
            "allow_negative_agreement" => false, "volume_share_pct" => share.round(6),
            "preferred_amount_min" => index.even? ? 500 : 25_000, "preferred_amount_max" => index.even? ? 50_000 : 200_000,
            "requests_per_minute_limit" => @name == "high_load" ? 3 : 60,
            "daily_turnover_min" => @name == "conflicting_goals" && index.zero? ? 2_000_000 : nil
          }
        end
        external.last["traffic_percentage"] += 100 - external.sum { |p| p["traffic_percentage"] }
        { "snapshot_at" => "2026-07-30T09:00:00+03:00", "gateway" => "RUB_SBP_WITHDRAW", "merchant" => "generated",
          "providers" => external + [ fallback_provider ] }
      end

      def fallback_provider
        { "payment_system" => "spacepayments", "status" => "active", "traffic_percentage" => 0, "priority" => 99,
          "limit_amount_min" => nil, "limit_amount_max" => nil, "daily_amount_limit" => nil, "daily_approved_amount" => 0,
          "in_progress_count_limit" => nil, "in_progress_count" => 0, "in_progress_amount_limit" => nil,
          "in_progress_amount" => 0, "available_requisites" => 20, "conversion_24h" => 0.96, "avg_latency_sec" => 12,
          "banks" => [], "exclude_banks" => false, "provider_margin_pct" => 0.5, "merchant_margin_pct" => 1.5,
          "allow_negative_agreement" => false }
      end

      def build_operations
        Array.new(@operation_count) do |index|
          amount = case @name when "hard_limits" then [ 499, 50_000, 200_001 ][index % 3] else @random.rand(500..180_000) end
          { "operation_id" => format("gen_%06d", index + 1),
            "created_at" => (Time.iso8601("2026-07-30T09:00:00+03:00") + index * 2).iso8601,
            "amount" => amount, "bank" => BANKS.sample(random: @random), "card_brand" => nil,
            "payout_requisite" => { "sbp" => { "phone" => format("7900%07d", @random.rand(10_000_000)), "bank_name" => "Generated" } } }
        end
      end

      def build_history(providers)
        names = providers["providers"].reject { |p| p["payment_system"] == "spacepayments" }.map { |p| p["payment_system"] }
        Array.new([ @operation_count, 100 ].min) do |index|
          [ format("hist_%04d", index + 1), "2026-07-29T09:00:00+03:00", @random.rand(500..100_000), BANKS.sample(random: @random), "",
            names.sample(random: @random), @random.rand < 0.75 ? "approved" : "rejected", @random.rand(5..120) ]
        end
      end

      def build_outcomes(operations, providers)
        external = providers["providers"].reject { |p| p["payment_system"] == "spacepayments" }
        outcomes = {}
        operations.each_with_index do |operation, index|
          external.each do |provider|
            next unless %w[timeouts fallback].include?(@name)

            result = @name == "timeouts" ? "expired" : "rejected"
            outcomes["#{operation['operation_id']}:#{provider['payment_system']}"] = { "result" => result,
              "latency_sec" => result == "expired" ? 300 : 20 + index % 10,
              "status_check_result" => result == "expired" ? "approved" : nil }.compact
          end
        end
        { "default" => { "result" => "approved", "latency_sec" => 12 }, "outcomes" => outcomes }
      end

      def corrupt!(providers, operations)
        providers["providers"][0]["traffic_percentage"] = -10
        providers["providers"][1]["payment_system"] = providers["providers"][0]["payment_system"] if providers["providers"][1]
        operations[0]["amount"] = -1
        operations[1]["operation_id"] = operations[0]["operation_id"] if operations[1]
      end
    end
  end
end
