# frozen_string_literal: true

module DuoRoute
  module DefaultSelection
    PATH = File.expand_path("../../config/routing/default_selection.json", __dir__)
    module_function

    def record
      JSON.parse(File.read(PATH))
    end

    def strategy = record.fetch("strategy")

    def evidence(preset, config)
      entry = record
      actual = config.fetch("presets").fetch(preset)
      matches = preset == entry["strategy"] && actual["weights"] == entry["weights"] && actual["policy_priorities"] == entry["policy_priorities"]
      { "strategy" => preset, "actual_weights" => actual["weights"], "policy_priorities" => actual["policy_priorities"],
        "matches_evaluated_default" => matches, "default_version" => entry["version"],
        "reason" => matches ? entry["reason"] : "Явная или сохранённая конфигурация; исследование default не доказывает преимущество этих настроек.",
        "default_evidence" => entry["evidence"] }
    end
  end
end
