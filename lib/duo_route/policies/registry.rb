# frozen_string_literal: true

module DuoRoute
  module Policies
    Score = Data.define(:name, :raw, :normalized, :explanation) do
      def to_h(weight)
        { "raw_value" => raw, "normalized_value" => normalized.round(6), "weight" => weight,
          "contribution" => (normalized * weight).round(6), "explanation" => explanation }
      end
    end

    class Base
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def result(raw, normalized, explanation)
        Score.new(name:, raw:, normalized: [ [ normalized.to_f, 0.0 ].max, 1.0 ].min, explanation:)
      end

      def utilization(current, limit)
        return 0.0 if limit.nil? || limit.to_f.zero?
        current.to_f / limit
      end
    end

    class CountShare < Base
      def initialize = super("count_share")
      def call(provider:, state:, **)
        projected_total = state.selected_total + 1
        projected = (state.selected_counts[provider["payment_system"]] + 1).to_f / projected_total * 100
        target = provider["traffic_percentage"].to_f
        result({ "projected_pct" => projected.round(4), "target_pct" => target }, 1 - ((projected - target).abs / 100),
          "projected count share #{projected.round(1)}% при цели #{target}%")
      end
    end

    class VolumeShare < Base
      def initialize = super("volume_share")
      def call(provider:, operation:, state:, **)
        target = provider["volume_share_pct"]
        return nil if target.nil?
        total = state.selected_volume_total + operation["amount"]
        projected = (state.selected_volumes[provider["payment_system"]] + operation["amount"]).to_f / total * 100
        result({ "projected_pct" => projected.round(4), "target_pct" => target }, 1 - ((projected - target).abs / 100),
          "projected volume share #{projected.round(1)}% при цели #{target}%")
      end
    end

    class Cascade < Base
      def initialize = super("cascade")
      def call(provider:, context:, **)
        priority = provider["priority"]
        return nil if priority.nil?
        priorities = context.fetch(:providers).filter_map { |item| item["priority"] }
        min, max = priorities.minmax
        normalized = max == min ? 1.0 : 1 - ((priority - min).to_f / (max - min))
        result(priority, normalized, "cascade priority #{priority} (меньше — раньше)")
      end
    end

    class PreferredAmount < Base
      def initialize = super("preferred_amount")
      def call(provider:, operation:, **)
        min = provider["preferred_amount_min"]
        max = provider["preferred_amount_max"]
        return nil if min.nil? && max.nil?
        amount = operation["amount"].to_f
        inside = (min.nil? || amount >= min) && (max.nil? || amount <= max)
        distance = if min && amount < min then (min - amount) / [ min.to_f, 1 ].max
        elsif max && amount > max then (amount - max) / [ max.to_f, 1 ].max else 0
        end
        result({ "amount" => amount, "preferred_min" => min, "preferred_max" => max }, inside ? 1.0 : 1 - distance,
          inside ? "сумма внутри предпочтительного диапазона" : "сумма вне предпочтительного диапазона")
      end
    end

    class Conversion < Base
      def initialize = super("conversion")
      def call(provider:, **)
        value = provider["effective_conversion"] || provider["conversion_24h"]
        return nil if value.nil?
        raw = { "value" => value, "source" => provider["effective_conversion"] ? "calibrated_history" : "provider_snapshot",
          "calibration" => provider["conversion_calibration"] }.compact
        result(raw, value, "ожидаемая конверсия #{(value * 100).round(1)}%; #{raw['source']}")
      end
    end

    class LoadSafe < Base
      def initialize = super("load_safe")
      def call(provider:, operation:, state:, **)
        current = state.for(provider["payment_system"])
        ratios = [ utilization(current["in_progress_count"] + 1, provider["in_progress_count_limit"]),
          utilization(current["in_progress_amount"] + operation["amount"], provider["in_progress_amount_limit"]),
          utilization(current["daily_approved_amount"] + operation["amount"], provider["daily_amount_limit"]) ]
        worst = ratios.max
        result(worst.round(6), 1 - [ worst, 1 ].min, "максимальная projected utilization #{(worst * 100).round(1)}%")
      end
    end

    class Intensity < Base
      def initialize = super("intensity")
      def call(provider:, operation:, state:, **)
        limit = provider["requests_per_minute_limit"]
        return nil if limit.nil?
        rpm = state.rpm(provider["payment_system"], Time.iso8601(operation["created_at"])) + 1
        ratio = rpm.to_f / limit
        result({ "projected_rpm" => rpm, "limit" => limit }, 1 - ratio, "projected RPM #{rpm}/#{limit}")
      end
    end

    class TurnoverCommitment < Base
      def initialize = super("turnover_commitment")
      def call(provider:, operation:, state:, **)
        min = provider["daily_turnover_min"]
        max = provider["daily_turnover_max"]
        return nil if min.nil? && max.nil?
        projected = state.for(provider["payment_system"])["daily_approved_amount"] + operation["amount"]
        normalized = if min && projected < min
          0.7 + 0.3 * (1 - projected.to_f / [ min, 1 ].max)
        elsif max && projected > max
          0.0
        else
          0.65
        end
        result({ "projected" => projected, "min" => min, "max" => max }, normalized,
          "projected turnover #{projected.round(2)}, коридор #{min || '—'}–#{max || '—'}")
      end
    end

    class Economy < Base
      def initialize = super("economy")
      def call(provider:, **)
        merchant = provider["merchant_margin_pct"]
        cost = provider["provider_margin_pct"]
        return nil if merchant.nil? || cost.nil?
        spread = merchant - cost
        result(spread.round(4), merchant.zero? ? 0 : spread / merchant, "маржинальный запас #{spread.round(2)} п.п.")
      end
    end

    class Latency < Base
      def initialize = super("latency")
      def call(provider:, context:, **)
        latency = provider["avg_latency_sec"]
        return nil if latency.nil?
        values = context.fetch(:providers).filter_map { |item| item["avg_latency_sec"] }
        maximum = values.max
        result(latency, maximum.zero? ? 1 : 1 - latency.to_f / maximum,
          "latency #{latency} с; максимум допустимого пула #{maximum} с")
      end
    end

    class Registry
      TYPES = [ CountShare, VolumeShare, Cascade, PreferredAmount, Conversion, LoadSafe,
        Intensity, TurnoverCommitment, Economy, Latency ].to_h { |type| [ type.new.name, type ] }.freeze

      def build(names)
        names.filter_map { |name| TYPES[name]&.new }
      end

      def names = TYPES.keys
    end
  end
end
