# frozen_string_literal: true

module DuoRoute
  ValidationIssue = Data.define(:path, :code, :message) do
    def to_h
      { "path" => path, "code" => code, "message" => message }
    end
  end

  class Error < StandardError; end

  class InputError < Error
    attr_reader :issues

    def initialize(issues)
      @issues = issues
      super(issues.map { |issue| "#{issue.path}: #{issue.message}" }.join("\n"))
    end
  end
end
