# frozen_string_literal: true

module DuoRoute
  class Runner
    attr_reader :providers_data, :operations, :config, :history

    def initialize(providers_data:, operations:, config:, history: [], preset: "balanced", seed: nil,
      outcomes: nil, progress: nil, settings: [])
      @raw_providers_data = deep_copy(providers_data)
      @operations = operations
      @config = Configuration.resolve(config, strategy: preset, settings:)
      @history = history
      @preset = preset
      @seed = Integer((seed || @config["seed"] || 42).to_s, exception: false)
      Configuration.fail!("seed", "ожидается целое неотрицательное число") unless @seed && @seed >= 0
      @config["seed"] = @seed
      @outcomes = outcomes
      @config["simulation"] = @config.fetch("simulation", {}).merge("source" => "scripted") if outcomes
      @progress = progress
      @providers_data = apply_overrides(@raw_providers_data)
    end

    def validate!
      issues = Validation::InputValidator.new.call(providers_data: @providers_data, operations:, config:, history:)
      issues << ValidationIssue.new(path: "$config.presets.#{@preset}", code: "unknown_preset", message: "preset не найден") unless config.fetch("presets", {}).key?(@preset)
      raise InputError, issues if issues.any?
      names = providers_data["providers"].map { |provider| provider["payment_system"] }
      user = config.fetch("user_configuration", {})
      submitted_names = user.fetch("provider_overrides", {}).keys + Array(user["settings"]).filter_map { |setting| setting.split(".")[1] if setting.start_with?("provider_overrides.") }
      submitted_names += config.dig("simulation", "providers")&.keys || []
      unknown = submitted_names.uniq - names
      Configuration.fail!("provider_overrides", "провайдеры не найдены: #{unknown.join(', ')}") if unknown.any?
      apply_calibration!
      fallback = config.dig("routing", "fallback_provider") || "spacepayments"
      Configuration.fail!("routing.fallback_provider", "провайдер не найден") unless providers_data["providers"].any? { |provider| provider["payment_system"] == fallback }
      @simulation = Simulation::Profile.new(providers: providers_data.fetch("providers"), history:, config: config.fetch("simulation", {}), seed: @seed, outcomes: @outcomes)
      validate_outcomes! if @simulation.source == "scripted"
      true
    end

    def call
      validate!
      simulator = if @simulation.source == "scripted"
        Simulation::Scripted.new(outcomes: @outcomes.fetch("outcomes", @outcomes), fallback: @outcomes["default"])
      else
        Simulation::Seeded.new(seed: @seed, profiles: @simulation.profiles)
      end
      manifest = {
        "providers_sha256" => digest(@raw_providers_data),
        "operations_sha256" => digest(operations),
        "config_sha256" => digest(config),
        "history_sha256" => history.empty? ? nil : digest(history.map { |row| row.reject { |key, _| key == "_line" } }),
        "outcomes_sha256" => @outcomes ? digest(@outcomes) : nil,
        "resolved_configuration" => config,
        "simulation" => @simulation.profiles,
        "seed" => @seed
      }.compact
      result = Engine.new(providers_data:, operations:, config:, preset: @preset, simulator:, history:, progress: @progress).call(manifest:)
      result.decisions.each do |decision|
        decision["simulation"] = @simulation.profiles.fetch(decision["selected_provider"])
        decision["attempts"].each { |attempt| attempt["simulation"] = @simulation.profiles[attempt["provider"]] if attempt.key?("result") }
      end
      result.report["simulation"] = @simulation.profiles
      result
    end

    private

    def validate_outcomes!
      Configuration.fail!("outcomes", "ожидается объект") unless @outcomes.is_a?(Hash)
      scripted = Simulation::Scripted.new(outcomes: @outcomes.fetch("outcomes", @outcomes), fallback: @outcomes["default"])
      Engine.new(providers_data:, operations:, config:, preset: @preset, simulator: scripted, history:).call
    rescue Error, KeyError, ArgumentError, TypeError, NoMethodError => e
      Configuration.fail!("outcomes", e.message)
    end

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
