# frozen_string_literal: true

module DuoRoute
  class Configuration
    def self.merge(base, changes)
      base.merge(changes) { |key, old, value| key != "weights" && old.is_a?(Hash) && value.is_a?(Hash) ? merge(old, value) : value }
    end

    def self.resolve(config, strategy:, settings: [])
      fail!("config", "ожидается объект") unless config.is_a?(Hash)
      validate_shape!(config)
      if config["resolved_strategy"] == strategy
        result = JSON.parse(JSON.generate(config))
        settings.each { |setting| set!(result, setting) }
        validate_shape!(result)
        result["user_configuration"] ||= {}
        result["user_configuration"]["settings"] = Array(result["user_configuration"]["settings"]) + settings
        return result
      end
      catalog = StrategyCatalog.all
      entry = catalog[strategy]
      defaults = entry ? entry.fetch("parameters").merge("presets" => { strategy => entry.slice("weights", "policy_priorities") }) : {}
      if %w[balanced custom].include?(strategy)
        defaults = catalog.values.reduce({}) { |combined, row| merge(combined, row.fetch("parameters")) }
      end
      common = Input::Loader.config_file(File.expand_path("../../config/routing/default.yml", __dir__)).slice("simulation", "routing")
      result = merge(merge(common, defaults), config)
      result["presets"] ||= {}
      catalog.each { |name, row| result["presets"][name] ||= row.slice("weights", "policy_priorities") }
      result["presets"]["custom"] ||= result["presets"]["balanced"] if result["presets"]["balanced"]
      settings.each { |setting| set!(result, setting) }
      validate_shape!(result)
      result["resolved_strategy"] = strategy
      result["user_configuration"] = JSON.parse(JSON.generate(config.reject { |key, _| %w[user_configuration resolved_strategy].include?(key) }))
      result["user_configuration"]["settings"] = settings.dup
      result
    end

    def self.set!(config, setting)
      path, raw = setting.split("=", 2)
      fail!(path, "ожидается path=value") unless raw && path.match?(/\A[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)*\z/)
      keys = path.split(".")
      parent = keys[0...-1].reduce(config) do |node, key|
        fail!(path, "родитель должен быть объектом") unless node.is_a?(Hash)
        node[key] ||= {}
      end
      fail!(path, "родитель должен быть объектом") unless parent.is_a?(Hash)
      parent[keys.last] = Input::Loader.config_string(raw)
    end

    def self.keys!(value, allowed, path)
      fail!(path, "ожидается объект") unless value.is_a?(Hash)
      unknown = value.keys - allowed
      fail!(path, "неизвестные параметры: #{unknown.join(', ')}") if unknown.any?
    end

    def self.validate_shape!(config)
      keys!(config, %w[schema_version routing simulation calibration provider_overrides presets resolved_strategy user_configuration input_metadata seed], "config")
      schemas = {
        "routing" => %w[fallback_provider timeout_mode],
        "simulation" => %w[source expired_rate minimum_samples latency_method failure_expired_share latency_spread_sec providers],
        "calibration" => %w[enabled minimum_samples prior_strength]
      }
      schemas.each { |key, allowed| keys!(config[key], allowed, key) if config.key?(key) }
      overrides = config.fetch("provider_overrides", {})
      fail!("provider_overrides", "ожидается объект") unless overrides.is_a?(Hash)
      allowed_provider = Validation::InputValidator::PROVIDER_REQUIRED + Validation::InputValidator::NUMERIC_FIELDS + %w[preferred_amount_min preferred_amount_max]
      overrides.each { |name, values| keys!(values, allowed_provider, "provider_overrides.#{name}") }
      presets = config.fetch("presets", {})
      fail!("presets", "ожидается объект") unless presets.is_a?(Hash)
      presets.each do |name, values|
        keys!(values, %w[weights policy_priorities], "presets.#{name}")
        priorities = values["policy_priorities"]
        if priorities && (!priorities.is_a?(Array) || priorities.uniq != priorities || (priorities - Validation::InputValidator::POLICY_NAMES).any?)
          fail!("presets.#{name}.policy_priorities", "ожидается массив уникальных известных факторов")
        end
      end
      custom = config.dig("simulation", "providers") || {}
      fail!("simulation.providers", "ожидается объект") unless custom.is_a?(Hash)
      custom.each { |name, values| keys!(values, %w[approved_rate rejected_rate expired_rate average_latency_sec latency_spread_sec], "simulation.providers.#{name}") }
      calibration = config.fetch("calibration", {})
      fail!("calibration.enabled", "ожидается boolean") if calibration.key?("enabled") && ![ true, false ].include?(calibration["enabled"])
      %w[minimum_samples prior_strength].each do |key|
        value = calibration[key]
        fail!("calibration.#{key}", "ожидается положительное число") if value && (!value.is_a?(Numeric) || !value.finite? || value <= 0)
      end
    end

    def self.fail!(path, message)
      raise InputError, [ ValidationIssue.new(path: "$#{path}", code: "invalid_configuration", message:) ]
    end
  end
end
