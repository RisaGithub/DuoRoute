# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "optparse"
require "fileutils"
require "tmpdir"
require "open3"
require "securerandom"
require "time"
require "yaml"

require_relative "duo_route/version"
require_relative "duo_route/error"
require_relative "duo_route/money"
require_relative "duo_route/reason_codes"
require_relative "duo_route/input/loader"
require_relative "duo_route/validation/input_validator"
require_relative "duo_route/state/store"
require_relative "duo_route/constraints/registry"
require_relative "duo_route/policies/registry"
require_relative "duo_route/scorer"
require_relative "duo_route/simulation/seeded"
require_relative "duo_route/simulation/scripted"
require_relative "duo_route/reporting/history_analyzer"
require_relative "duo_route/reporting/recommendation_engine"
require_relative "duo_route/reporting/goal_feasibility"
require_relative "duo_route/reporting/report_builder"
require_relative "duo_route/reporting/comparison_metrics"
require_relative "duo_route/reporting/output_validator"
require_relative "duo_route/generators/scenario"
require_relative "duo_route/engine"
require_relative "duo_route/strategy_catalog"
require_relative "duo_route/configuration"
require_relative "duo_route/simulation/profile"
require_relative "duo_route/default_selection"
require_relative "duo_route/runner"
require_relative "duo_route/evaluation/default_strategy"
require_relative "duo_route/evaluation/robustness"
require_relative "duo_route/evaluation/strategy_comparison"
require_relative "duo_route/cli/app"
require_relative "duo_route/cli/readiness"

module DuoRoute
  DecimalLiteral = Data.define(:text) do
    def to_json(*) = text
  end

  module_function

  def pretty_json(value)
    JSON.pretty_generate(json_decimal_literals(value), allow_nan: false) + "\n"
  end

  # JSON 2.21 may emit 7.6645200000000004 for Float 7.66452. Preserve the
  # decimal representation validated by Money instead of introducing a tail.
  def json_decimal_literals(value)
    case value
    when Float
      raise Error, "JSON number must be finite" unless value.finite?
      DecimalLiteral.new(value.to_s)
    when Hash then value.transform_values { |item| json_decimal_literals(item) }
    when Array then value.map { |item| json_decimal_literals(item) }
    else value
    end
  end
end
