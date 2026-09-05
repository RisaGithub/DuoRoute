# frozen_string_literal: true

module DuoRoute
  module Simulation
    Outcome = Data.define(:result, :latency_sec, :status_check_result) do
      def to_h = { "result" => result, "latency_sec" => latency_sec, "status_check_result" => status_check_result }.compact
    end

    class Seeded
      def initialize(seed:, expired_rate: 0.04)
        @seed = seed.to_i
        @expired_rate = expired_rate.to_f
      end

      def call(operation:, provider:, attempt:)
        value = unit("result", operation["operation_id"], provider["payment_system"], attempt)
        conversion = provider["effective_conversion"] || provider["conversion_24h"]
        result = if value < conversion.to_f then "approved"
        elsif value < conversion.to_f + @expired_rate then "expired" else "rejected"
        end
        average = provider["avg_latency_sec"].to_f
        latency = result == "expired" ? [ (average * 8).round, 120 ].max : [ (average * (0.55 + unit("latency", operation["operation_id"], provider["payment_system"], attempt))).round, 1 ].max
        status_check = result == "expired" ? (unit("status", operation["operation_id"], provider["payment_system"], attempt) < conversion.to_f ? "approved" : "rejected") : nil
        Outcome.new(result:, latency_sec: latency, status_check_result: status_check)
      end

      private

      def unit(*parts)
        Digest::SHA256.hexdigest([ @seed, *parts ].join(":"))[0, 16].to_i(16).to_f / 0xffffffffffffffff
      end
    end
  end
end
