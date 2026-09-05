# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "optparse"
require "fileutils"
require "securerandom"
require "time"
require "yaml"

require_relative "duo_route/version"
require_relative "duo_route/error"
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
require_relative "duo_route/reporting/report_builder"
require_relative "duo_route/reporting/output_validator"
require_relative "duo_route/generators/scenario"
require_relative "duo_route/engine"
require_relative "duo_route/strategy_catalog"
require_relative "duo_route/configuration"
require_relative "duo_route/simulation/profile"
require_relative "duo_route/runner"
require_relative "duo_route/cli/app"

module DuoRoute
  module_function

  def pretty_json(value)
    JSON.pretty_generate(value, allow_nan: false) + "\n"
  end
end
