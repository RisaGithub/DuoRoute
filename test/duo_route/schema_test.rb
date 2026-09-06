# frozen_string_literal: true

require "test_helper"
require_relative "../../script/check_schemas"

class SchemaTest < ActiveSupport::TestCase
  test "all six schemas accept real examples and freshly produced audit levels" do
    config = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml"))
    data = DuoRoute::Input::Loader.json_file(Rails.root.join("data/providers.json"))
    operations = DuoRoute::Input::Loader.json_file(Rails.root.join("data/operations_queue_10.json"))
    outcomes = DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/demo_outcomes.json"))
    schemas = %w[providers operations routing_config routing_decisions routing_report outcomes].to_h { |name| [ name, JSON.parse(Rails.root.join("schemas", "#{name}.schema.json").read) ] }
    %w[full submission compact].each do |level|
      result = DuoRoute::Runner.new(providers_data: data, operations:, config:, outcomes:, audit_level: level).call
      { "providers" => data, "operations" => operations, "routing_config" => result.manifest["resolved_configuration"],
        "outcomes" => outcomes, "routing_decisions" => result.decisions, "routing_report" => result.report }.each do |name, value|
        assert_empty SchemaCheck.validate(value, schemas[name]), name
      end
      result.decisions[0]["attempts"][0]["decision"] = "bad"
      assert_not_empty SchemaCheck.validate(result.decisions, schemas["routing_decisions"])
    end
    operations[0]["amount"] = -1
    assert_not_empty SchemaCheck.validate(operations, schemas["operations"])
    data["providers"][0]["in_progress_count"] = 0.5
    assert_not_empty SchemaCheck.validate(data, schemas["providers"])
    config["unknown"] = true
    assert_not_empty SchemaCheck.validate(config, schemas["routing_config"])
  end
end
