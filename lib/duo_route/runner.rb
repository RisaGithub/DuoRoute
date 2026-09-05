# frozen_string_literal: true

module DuoRoute
  class Runner
    attr_reader :providers_data, :operations, :config, :history

    def initialize(providers_data:, operations:, config:, history: [], preset: "balanced", seed: 42,
      outcomes: nil, progress: nil)
      @raw_providers_data = deep_copy(providers_data)
      @operations = operations
      @config = config
      @history = history
      @preset = preset
      @seed = seed.to_i
      @outcomes = outcomes
      @progress = progress
      @providers_data = apply_overrides(@raw_providers_data)
      apply_calibration!
    end

    def validate!
      issues = Validation::InputValidator.new.call(providers_data: @providers_data, operations:, config:, history:)
      issues << ValidationIssue.new(path: "$config.presets.#{@preset}", code: "unknown_preset", message: "preset не найден") unless config.fetch("presets", {}).key?(@preset)
      raise InputError, issues if issues.any?
      true
    end

    def call
      validate!
      simulator = if @outcomes
        Simulation::Scripted.new(outcomes: @outcomes.fetch("outcomes", @outcomes), fallback: @outcomes["default"])
      else
        Simulation::Seeded.new(seed: @seed, expired_rate: config.dig("simulation", "expired_rate") || 0.04)
      end
      manifest = {
        "providers_sha256" => digest(@raw_providers_data),
        "operations_sha256" => digest(operations),
        "config_sha256" => digest(config),
        "history_sha256" => history.empty? ? nil : digest(history.map { |row| row.reject { |key, _| key == "_line" } }),
        "outcomes_sha256" => @outcomes ? digest(@outcomes) : nil,
        "seed" => @seed
      }.compact
      Engine.new(providers_data:, operations:, config:, preset: @preset, simulator:, history:, progress: @progress).call(manifest:)
    end

    private

    def apply_overrides(data)
      overrides = config.fetch("provider_overrides", {})
      return data unless data.is_a?(Hash) && data["providers"].is_a?(Array)

      data.merge("providers" => data["providers"].map do |provider|
        next provider unless provider.is_a?(Hash)
        provider.merge(overrides.fetch(provider["payment_system"], {}))
      end)
    end

    def apply_calibration!
      calibration = config.fetch("calibration", {})
      return unless calibration["enabled"]
      @providers_data["providers"] = Reporting::HistoryAnalyzer.new(history).calibrated(@providers_data["providers"],
        minimum_samples: calibration.fetch("minimum_samples", 20), prior_strength: calibration.fetch("prior_strength", 30).to_f)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [ key, canonical(value[key]) ] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def deep_copy(value) = JSON.parse(JSON.generate(value))
  end
end
