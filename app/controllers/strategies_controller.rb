# frozen_string_literal: true

class StrategiesController < ApplicationController
  def show
    @config = routing_config
    @comparison = nil
  end

  def compare
    @config = routing_config
    providers = DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/providers.json").to_s)
    operations = DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/operations_queue_10.json").to_s)
    presets = Array(params[:presets]).intersection(@config.fetch("presets").keys)
    @comparison = presets.map do |preset|
      result = DuoRoute::Runner.new(providers_data: providers, operations:, config: @config, preset:, seed: params[:seed] || 42).call
      { name: preset, report: result.report }
    end
    render :show
  end

  private

  def routing_config = DuoRoute::Configuration.resolve(DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s), strategy: "balanced")
end
