# frozen_string_literal: true

class StrategySetting < ApplicationRecord
  validates :name, inclusion: { in: DuoRoute::StrategyCatalog.all.keys }, uniqueness: true
  validate :valid_parameters

  def self.catalog
    entries = DuoRoute::StrategyCatalog.all
    all.each do |setting|
      entries.fetch(setting.name)["parameters"]["provider_overrides"] = setting.provider_overrides
    end
    entries
  end

  def self.apply(config, strategy)
    entries = catalog
    defaults = if %w[balanced custom].include?(strategy)
      entries.values.reduce({}) { |result, entry| DuoRoute::Configuration.merge(result, entry.fetch("parameters")) }
    else
      entries.dig(strategy, "parameters") || {}
    end
    DuoRoute::Configuration.merge(defaults, config)
  end

  private

  def valid_parameters
    template = DuoRoute::StrategyCatalog.all.dig(name, "parameters", "provider_overrides")
    return unless template
    unless provider_overrides.is_a?(Hash) && provider_overrides.keys.sort == template.keys.sort && template.all? { |provider, fields| provider_overrides[provider].is_a?(Hash) && provider_overrides[provider].keys.sort == fields.keys.sort }
      errors.add(:base, "Набор параметров должен соответствовать стратегии")
      return
    end
    provider_overrides.each do |provider, fields|
      fields.each do |key, value|
        next if value.nil? && template[provider][key].nil?
        unless value.is_a?(Numeric) && value.finite? && value >= 0
          errors.add(:base, "#{provider} · #{key}: введите неотрицательное число")
          next
        end
        errors.add(:base, "#{provider} · #{key}: максимум 100%") if %w[traffic_percentage volume_share_pct].include?(key) && value > 100
        errors.add(:base, "#{provider} · #{key}: введите целое число от 1") if %w[priority requests_per_minute_limit].include?(key) && (value < 1 || value != value.to_i)
      end
      low, high = fields.values_at("preferred_amount_min", "preferred_amount_max")
      errors.add(:base, "#{provider}: нижняя граница больше верхней") if low.is_a?(Numeric) && high.is_a?(Numeric) && low > high
    end
    %w[traffic_percentage volume_share_pct].each do |field|
      values = provider_overrides.values.filter_map { |fields| fields[field] }
      if values.any? && values.all? { |value| value.is_a?(Numeric) } && (values.sum - 100).abs > 0.001
        errors.add(:base, "Сумма долей должна быть равна 100%")
      end
    end
  end
end
