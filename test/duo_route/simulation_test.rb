# frozen_string_literal: true

require "test_helper"

class SimulationTest < ActiveSupport::TestCase
  test "seeded simulator is deterministic" do
    simulator = DuoRoute::Simulation::Seeded.new(seed: 42)
    one = simulator.call(operation:, provider:, attempt: 1)
    two = simulator.call(operation:, provider:, attempt: 1)
    assert_equal one, two
    assert_includes %w[approved rejected expired], one.result
  end

  test "different seeds can produce different deterministic stream" do
    values = (1..20).map do |seed|
      DuoRoute::Simulation::Seeded.new(seed:).call(operation:, provider:, attempt: 1).to_h
    end
    assert_operator values.uniq.length, :>, 1
  end

  test "scripted simulator supports flat and nested maps" do
    flat = DuoRoute::Simulation::Scripted.new(outcomes: { "op_1:alpha" => { "result" => "rejected", "latency_sec" => 7 } })
    assert_equal "rejected", flat.call(operation:, provider:, attempt: 1).result
    nested = DuoRoute::Simulation::Scripted.new(outcomes: { "op_1" => { "alpha" => "approved" } })
    assert_equal "approved", nested.call(operation:, provider:, attempt: 2).result
  end

  test "scripted simulator rejects unknown enum and missing outcome" do
    assert_raises(DuoRoute::Error) { DuoRoute::Simulation::Scripted.new(outcomes: {}).call(operation:, provider:, attempt: 1) }
    assert_raises(DuoRoute::Error) do
      DuoRoute::Simulation::Scripted.new(outcomes: { "op_1:alpha" => "unknown" }).call(operation:, provider:, attempt: 1)
    end
  end
end
