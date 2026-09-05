# frozen_string_literal: true

module DuoRoute
  class StrategyCatalog
    PATH = File.expand_path("../../config/routing/strategies.yml", __dir__)

    def self.all
      entries = Input::Loader.config_file(PATH)
      unless entries.is_a?(Hash) && entries.size == 7 && entries.all? { |name, row| valid_entry?(name, row) }
        raise Error, "Некорректный каталог семи стратегий"
      end
      entries
    end

    def self.valid_entry?(name, row)
      return false unless row.is_a?(Hash) && row["name"] == name
      return false unless %w[title description example].all? { |key| row[key].is_a?(String) && !row[key].empty? }
      weights = row["weights"]
      return false unless weights.is_a?(Hash) && weights.any? && weights.values.all? { |weight| weight.is_a?(Numeric) && weight.finite? && weight.positive? }
      return false unless (weights.keys - Validation::InputValidator::POLICY_NAMES).empty?
      return false unless row["policies"] == weights.keys && row["policy_priorities"].is_a?(Array) && row["policy_priorities"].sort == weights.keys.sort
      row["parameters"].is_a?(Hash) && row["parameters"]["provider_overrides"].is_a?(Hash)
    end
  end
end
