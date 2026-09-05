# frozen_string_literal: true

module DuoRoute
  module Constraints
    Check = Data.define(:eligible, :code, :explanation, :actual, :threshold) do
      def to_h
        { "eligible" => eligible, "code" => code, "explanation" => explanation,
          "actual" => actual, "threshold" => threshold }
      end
    end

    class Base
      def pass(explanation, actual: nil, threshold: nil)
        Check.new(eligible: true, code: "eligible", explanation:, actual:, threshold:)
      end

      def fail(code, explanation, actual:, threshold:)
        Check.new(eligible: false, code:, explanation:, actual:, threshold:)
      end
    end

    class Status < Base
      def call(provider:, **)
        return pass("провайдер активен", actual: provider["status"], threshold: "active") if provider["status"] == "active"
        fail("provider_inactive", "статус провайдера не active", actual: provider["status"], threshold: "active")
      end
    end

    class AmountMinimum < Base
      def call(provider:, operation:, **)
        limit = provider["limit_amount_min"]
        return pass("минимум не задан или соблюдён", actual: operation["amount"], threshold: limit) if limit.nil? || Money.decimal(operation["amount"]) >= Money.decimal(limit)
        fail("amount_below_minimum", "#{operation['amount']} < limit_amount_min #{limit}", actual: operation["amount"], threshold: limit)
      end
    end

    class AmountMaximum < Base
      def call(provider:, operation:, **)
        limit = provider["limit_amount_max"]
        return pass("максимум не задан или соблюдён", actual: operation["amount"], threshold: limit) if limit.nil? || Money.decimal(operation["amount"]) <= Money.decimal(limit)
        fail("amount_exceeds_limit", "#{operation['amount']} > limit_amount_max #{limit}", actual: operation["amount"], threshold: limit)
      end
    end

    class DailyAmount < Base
      def call(provider:, operation:, state:, **)
        limit = provider["daily_amount_limit"]
        projected = state.for(provider["payment_system"])["daily_approved_amount"] + Money.decimal(operation["amount"])
        return pass("дневной лимит не задан или соблюдён", actual: projected, threshold: limit) if limit.nil? || projected <= Money.decimal(limit)
        fail("daily_amount_limit_exceeded", "projected daily #{projected} > #{limit}", actual: projected, threshold: limit)
      end
    end

    class InProgressCount < Base
      def call(provider:, state:, **)
        limit = provider["in_progress_count_limit"]
        projected = state.for(provider["payment_system"])["in_progress_count"] + 1
        return pass("лимит in-progress count не задан или соблюдён", actual: projected, threshold: limit) if limit.nil? || projected <= Money.decimal(limit)
        fail("in_progress_count_limit_exceeded", "projected in-progress count #{projected} > #{limit}", actual: projected, threshold: limit)
      end
    end

    class InProgressAmount < Base
      def call(provider:, operation:, state:, **)
        limit = provider["in_progress_amount_limit"]
        projected = state.for(provider["payment_system"])["in_progress_amount"] + Money.decimal(operation["amount"])
        return pass("лимит in-progress amount не задан или соблюдён", actual: projected, threshold: limit) if limit.nil? || projected <= Money.decimal(limit)
        fail("in_progress_amount_limit_exceeded", "projected in-progress amount #{projected} > #{limit}", actual: projected, threshold: limit)
      end
    end

    class Bank < Base
      def call(provider:, operation:, **)
        banks = provider["banks"] || []
        return pass("банковское ограничение не задано", actual: operation["bank"], threshold: []) if banks.empty?
        if provider["exclude_banks"]
          return fail("bank_excluded", "банк #{operation['bank']} находится в exclude list", actual: operation["bank"], threshold: banks) if banks.include?(operation["bank"])
        elsif !banks.include?(operation["bank"])
          return fail("bank_not_in_list", "банк #{operation['bank']} отсутствует в include list", actual: operation["bank"], threshold: banks)
        end
        pass("банк разрешён", actual: operation["bank"], threshold: banks)
      end
    end

    class Margin < Base
      def call(provider:, **)
        actual = provider["provider_margin_pct"]
        threshold = provider["merchant_margin_pct"]
        return pass("маржинальное соглашение соблюдено", actual:, threshold:) if provider["allow_negative_agreement"] || Money.decimal(actual) <= Money.decimal(threshold)
        fail("negative_margin_not_allowed", "provider margin #{actual}% > merchant margin #{threshold}%", actual:, threshold:)
      end
    end

    class Requisites < Base
      def call(provider:, **)
        actual = provider["available_requisites"]
        return pass("есть доступные реквизиты", actual:, threshold: 1) if actual.positive?
        fail("no_available_requisites", "нет доступных реквизитов", actual:, threshold: 1)
      end
    end

    class RateLimit < Base
      def call(provider:, operation:, state:, **)
        limit = provider["requests_per_minute_limit"]
        actual = state.rpm(provider["payment_system"], Time.iso8601(operation["created_at"])) + 1
        return pass("RPM limit не задан или соблюдён", actual:, threshold: limit) if limit.nil? || actual <= limit
        fail("rate_limit_exceeded", "projected RPM #{actual} > #{limit}", actual:, threshold: limit)
      end
    end

    class Registry
      DEFAULTS = [ Status, AmountMinimum, AmountMaximum, DailyAmount, InProgressCount,
        InProgressAmount, Bank, Margin, Requisites, RateLimit ].freeze

      def initialize(constraints = DEFAULTS.map(&:new))
        @constraints = constraints
      end

      def evaluate(provider:, operation:, state:)
        checks = @constraints.map { |constraint| constraint.call(provider:, operation:, state:) }
        { "eligible" => checks.all?(&:eligible), "checks" => checks.map(&:to_h),
          "failures" => checks.reject(&:eligible).map(&:to_h) }
      end
    end
  end
end
