#!/usr/bin/env ruby
# frozen_string_literal: true

require "objspace"
require_relative "../lib/duo_route"

bundle = DuoRoute::Generators::Scenario.new(name: "stress", operations: Integer(ARGV.fetch(0, "1000")), providers: 20, seed: 42).call
config = DuoRoute::Input::Loader.config_file(File.expand_path("../config/routing/default.yml", __dir__))
result = DuoRoute::Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], config:, audit_level: ARGV.fetch(1, "full")).call

def retained_size(value, seen = {})
  return 0 if seen[value.object_id]
  seen[value.object_id] = true
  size = ObjectSpace.memsize_of(value)
  case value
  when Hash then value.each { |k, v| size += retained_size(k, seen) + retained_size(v, seen) }
  when Array then value.each { |v| size += retained_size(v, seen) }
  end
  size
end

puts DuoRoute.pretty_json("operations" => result.decisions.size, "audit_level" => ARGV.fetch(1, "full"),
  "decision_retained_bytes" => retained_size(result.decisions),
  "fields_retained_bytes" => result.decisions.first.keys.to_h { |key| [ key, retained_size(result.decisions.map { |row| row[key] }) ] },
  "json_bytes" => JSON.generate(result.decisions).bytesize,
  "note" => "ObjectSpace retained size; fields overlap through shared objects; not peak RSS.")
