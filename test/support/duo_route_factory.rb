# frozen_string_literal: true

module DuoRouteFactory
  def provider(name = "alpha", **changes)
    {
      "payment_system" => name, "status" => "active", "traffic_percentage" => name == "spacepayments" ? 0 : 100,
      "priority" => 1, "limit_amount_min" => 100, "limit_amount_max" => 1000,
      "daily_amount_limit" => 10_000, "daily_approved_amount" => 1000,
      "in_progress_count_limit" => 3, "in_progress_count" => 0,
      "in_progress_amount_limit" => 3000, "in_progress_amount" => 0,
      "available_requisites" => 2, "conversion_24h" => 0.8, "avg_latency_sec" => 20,
      "banks" => [], "exclude_banks" => false, "provider_margin_pct" => 1.0,
      "merchant_margin_pct" => 1.5, "allow_negative_agreement" => false
    }.merge(changes.transform_keys(&:to_s))
  end

  def providers_data(externals = [ provider ], fallback: provider("spacepayments", limit_amount_min: nil, limit_amount_max: nil,
    daily_amount_limit: nil, in_progress_count_limit: nil, in_progress_amount_limit: nil))
    { "snapshot_at" => "2026-07-30T09:00:00+03:00", "gateway" => "RUB", "merchant" => "test",
      "providers" => externals + [ fallback ] }
  end

  def operation(id = "op_1", **changes)
    { "operation_id" => id, "created_at" => "2026-07-30T09:05:00+03:00", "amount" => 500, "bank" => "sberbank" }
      .merge(changes.transform_keys(&:to_s))
  end

  def config(weights = { "count_share" => 1.0 }, timeout: "fallback_on_timeout", overrides: {})
    { "routing" => { "fallback_provider" => "spacepayments", "timeout_mode" => timeout },
      "simulation" => { "expired_rate" => 0.04 }, "provider_overrides" => overrides,
      "presets" => { "balanced" => { "weights" => weights } } }
  end

  def state_for(providers)
    DuoRoute::State::Store.new(providers)
  end
end

class ActiveSupport::TestCase
  include DuoRouteFactory
end
