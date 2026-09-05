# frozen_string_literal: true

module DuoRoute
  class Scorer
    def initialize(weights:, policy_priorities: nil, registry: Policies::Registry.new)
      @weights = weights.transform_values(&:to_f)
      @policy_priorities = policy_priorities || @weights.keys
      @policies = registry.build(@weights.keys)
    end

    def rank(providers:, operation:, state:)
      rows = providers.map { |provider| score(provider:, providers:, operation:, state:) }
      rows.sort_by do |row|
        priority_vector = @policy_priorities.map { |name| -(row["score_breakdown"].dig(name, "normalized_value") || -1) }
        [ -row["combined_score"], *priority_vector, row["provider_priority"] || 999_999, row["provider"] ]
      end.each_with_index { |row, index| row["rank"] = index + 1 }
    end

    private

    def score(provider:, providers:, operation:, state:)
      scores = @policies.filter_map do |policy|
        item = policy.call(provider:, operation:, state:, context: { providers: })
        [ policy.name, item ] if item
      end.to_h
      denominator = scores.sum { |name, _| @weights.fetch(name, 0) }
      combined = denominator.zero? ? 0.0 : scores.sum { |name, value| value.normalized * @weights.fetch(name, 0) } / denominator
      {
        "provider" => provider["payment_system"],
        "combined_score" => combined.round(6),
        "provider_priority" => provider["priority"],
        "score_breakdown" => scores.transform_values { |value| value.to_h(@weights.fetch(value.name, 0)) }
      }
    end
  end
end
