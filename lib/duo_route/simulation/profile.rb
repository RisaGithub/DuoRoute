# frozen_string_literal: true

module DuoRoute
  module Simulation
    class Profile
      SOURCES = %w[history provider_snapshot custom scripted].freeze
      attr_reader :profiles, :source

      def initialize(providers:, history:, config:, seed:, outcomes: nil)
        @config = config
        @seed = seed
        @source = config.fetch("source", outcomes ? "scripted" : "history")
        Configuration.fail!("simulation.source", "неизвестный источник") unless SOURCES.include?(@source)
        Configuration.fail!("simulation.source", "scripted требует outcomes.json") if @source == "scripted" && !outcomes
        if @config.key?("expired_rate")
          number!("expired_rate", @config["expired_rate"], 0, 1)
        end
        minimum = @config.fetch("minimum_samples", 20)
        Configuration.fail!("simulation.minimum_samples", "ожидается положительное целое число") unless minimum.is_a?(Integer) && minimum.positive?
        Configuration.fail!("simulation.latency_method", "допустимы mean и median") unless %w[mean median].include?(@config.fetch("latency_method", "mean"))
        number!("failure_expired_share", @config.fetch("failure_expired_share", 0.2), 0, 1)
        number!("latency_spread_sec", @config.fetch("latency_spread_sec", 0), 0, Float::INFINITY)
        @profiles = providers.to_h { |provider| [ provider.fetch("payment_system"), profile(provider, history) ] }
      end

      def profile(provider, history)
        return { "source" => "scripted", "requested_source" => "scripted", "probabilities_applied" => false, "history_records" => 0, "provider_snapshot_fallback" => false, "seed" => @seed } if @source == "scripted"
        rows = history.select { |row| row["payment_system"] == provider["payment_system"] }
        minimum = @config.fetch("minimum_samples", 20)
        Configuration.fail!("simulation.minimum_samples", "ожидается положительное целое число") unless minimum.is_a?(Integer) && minimum.positive?
        method = @config.fetch("latency_method", "mean")
        Configuration.fail!("simulation.latency_method", "допустимы mean и median") unless %w[mean median].include?(method)
        use_history = @source == "history" && rows.length >= minimum
        approved = use_history ? rows.count { |row| row["status"] == "approved" }.fdiv(rows.length) : provider["conversion_24h"].to_f
        split = @config.fetch("failure_expired_share", 0.2)
        number!("failure_expired_share", split, 0, 1)
        expired = use_history ? rows.count { |row| row["status"] == "expired" }.fdiv(rows.length) : (1 - approved) * split
        expired = [ @config["expired_rate"], 1 - approved ].min if !use_history && @config.key?("expired_rate")
        latencies = rows.map { |row| row["latency_sec"].to_f }.sort
        average = if use_history
          method == "median" ? (latencies[(latencies.length - 1) / 2] + latencies[latencies.length / 2]) / 2 : latencies.sum / latencies.length
        else
          provider["avg_latency_sec"].to_f
        end
        values = { "approved_rate" => approved, "rejected_rate" => 1 - approved - expired, "expired_rate" => expired,
          "average_latency_sec" => average, "latency_spread_sec" => @config.fetch("latency_spread_sec", 0) }
        if @source == "custom"
          custom = @config.fetch("providers", {}).fetch(provider["payment_system"], nil)
          Configuration.fail!("simulation.providers.#{provider['payment_system']}", "задайте собственные вероятности") unless custom.is_a?(Hash) && custom.key?("approved_rate")
          if !custom.key?("expired_rate") && !custom.key?("rejected_rate")
            number!("approved_rate", custom["approved_rate"], 0, 1)
            custom = custom.merge("expired_rate" => (1 - custom["approved_rate"]) * split, "rejected_rate" => (1 - custom["approved_rate"]) * (1 - split))
          elsif !custom.key?("expired_rate") || !custom.key?("rejected_rate")
            Configuration.fail!("simulation.providers", "задайте все три вероятности либо только Approval")
          end
          values.merge!(custom)
        end
        %w[approved_rate rejected_rate expired_rate].each { |key| number!(key, values[key], -1e-12, 1) }
        Configuration.fail!("simulation.providers", "сумма вероятностей должна быть равна 100% (1.0)") unless (values.values_at("approved_rate", "rejected_rate", "expired_rate").sum - 1).abs < 1e-9
        %w[average_latency_sec latency_spread_sec].each { |key| number!(key, values[key], 0, Float::INFINITY) }
        values.merge("source" => @source == "history" && !use_history ? "provider_snapshot" : @source,
          "requested_source" => @source, "history_records" => use_history ? rows.length : 0,
          "available_history_records" => rows.length, "provider_snapshot_fallback" => @source == "history" && !use_history, "seed" => @seed)
      end

      def number!(key, value, min, max)
        Configuration.fail!("simulation.#{key}", "значение вне допустимого диапазона") unless value.is_a?(Numeric) && value.finite? && value.between?(min, max)
      end
    end
  end
end
