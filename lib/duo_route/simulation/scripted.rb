# frozen_string_literal: true

module DuoRoute
  module Simulation
    class Scripted
      def initialize(outcomes:, fallback: nil)
        @outcomes = outcomes
        @fallback = fallback
      end

      def call(operation:, provider:, attempt:)
        key = "#{operation['operation_id']}:#{provider['payment_system']}"
        raw = @outcomes[key] || @outcomes.dig(operation["operation_id"], provider["payment_system"]) || @fallback
        raise Error, "scripted outcome отсутствует для #{key}" unless raw
        raw = { "result" => raw } if raw.is_a?(String)
        result = raw.fetch("result")
        raise Error, "недопустимый scripted result #{result}" unless %w[approved rejected expired].include?(result)
        latency = Integer(raw["latency_sec"] || attempt)
        raise Error, "scripted latency должна быть неотрицательной" if latency.negative?
        raise Error, "неверный status_check_result" unless [ nil, "approved", "rejected" ].include?(raw["status_check_result"])
        Outcome.new(result:, latency_sec: latency, status_check_result: raw["status_check_result"])
      end
    end
  end
end
