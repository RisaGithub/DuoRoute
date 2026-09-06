#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Small, fail-closed evaluator for the JSON Schema keywords used by this repository.
# Not a general JSON Schema engine; semantic checks remain in the core/auditor.
class SchemaCheck
  KEYWORDS = %w[$schema title description type properties required additionalProperties items minItems minLength minimum maximum exclusiveMinimum enum anyOf].freeze
  def self.validate(value, schema, path = "$")
    unknown = schema.keys - KEYWORDS
    raise ArgumentError, "unsupported schema keywords: #{unknown.join(', ')}" if unknown.any?
    return [ "#{path}: anyOf" ] if schema["anyOf"] && schema["anyOf"].none? { |s| validate(value, s, path).empty? }
    errors = []
    errors << "#{path}: enum" if schema["enum"] && !schema["enum"].include?(value)
    kind = schema["type"]
    valid = case kind
    when "object" then value.is_a?(Hash)
    when "array" then value.is_a?(Array)
    when "string" then value.is_a?(String)
    when "number" then value.is_a?(Numeric) && value.finite?
    when "integer" then value.is_a?(Numeric) && value.finite? && value == value.to_i
    when "boolean" then [ true, false ].include?(value)
    when "null" then value.nil?
    when nil then true
    else raise ArgumentError, "unsupported schema type"
    end
    return errors + [ "#{path}: type #{kind}" ] unless valid
    if value.is_a?(Hash)
      Array(schema["required"]).each { |k| errors << "#{path}.#{k}: required" unless value.key?(k) }
      value.each do |k, v|
        property = schema.fetch("properties", {})[k]
        if property
          errors.concat(validate(v, property, "#{path}.#{k}"))
        elsif schema["additionalProperties"] == false
          errors << "#{path}.#{k}: unknown property"
        elsif schema["additionalProperties"].is_a?(Hash)
          errors.concat(validate(v, schema["additionalProperties"], "#{path}.#{k}"))
        end
      end
    elsif value.is_a?(Array)
      errors << "#{path}: minItems" if schema["minItems"] && value.size < schema["minItems"]
      value.each_with_index { |v, i| errors.concat(validate(v, schema["items"], "#{path}[#{i}]")) } if schema["items"]
    elsif value.is_a?(String)
      errors << "#{path}: minLength" if schema["minLength"] && value.size < schema["minLength"]
    elsif value.is_a?(Numeric)
      errors << "#{path}: minimum" if schema["minimum"] && value < schema["minimum"]
      errors << "#{path}: maximum" if schema["maximum"] && value > schema["maximum"]
      errors << "#{path}: exclusiveMinimum" if schema["exclusiveMinimum"] && value <= schema["exclusiveMinimum"]
    end
    errors
  end
end

if $PROGRAM_NAME == __FILE__
  abort "usage: ruby script/check_schemas.rb SCHEMA JSON" unless ARGV.size == 2
  errors = SchemaCheck.validate(JSON.parse(File.read(ARGV[1])), JSON.parse(File.read(ARGV[0])))
  abort errors.join("\n") unless errors.empty?
  puts "SCHEMA PASS"
end
