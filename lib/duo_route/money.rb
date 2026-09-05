# frozen_string_literal: true

require "bigdecimal"

module DuoRoute
  # Decimal arithmetic internally; JSON keeps numeric fields, never decimal strings.
  module Money
    module_function

    def decimal(value)
      value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
    end

    def sum(values)
      values.sum(BigDecimal("0")) { |value| decimal(value) }
    end

    def number(value)
      exact = decimal(value)
      raise Error, "денежное значение не является конечным" unless exact.finite?
      return exact.to_i if exact.frac.zero?
      result = exact.to_f
      unless result.finite? && decimal(result) == exact
        raise Error, "денежное значение #{exact.to_s('F')} нельзя точно представить числом JSON в текущем интерфейсе"
      end
      result
    end

    def json_numbers(value)
      case value
      when BigDecimal then number(value)
      when Hash then value.transform_values! { |item| json_numbers(item) }
      when Array then value.map! { |item| json_numbers(item) }
      else value
      end
    end
  end
end
