# frozen_string_literal: true

class ProvidersController < ApplicationController
  before_action :load_run

  def index
    @providers = @run ? @run.providers.fetch("providers", []) : example_providers
  end

  def show
    @provider = (@run ? @run.providers.fetch("providers", []) : example_providers)
      .find { |provider| provider["payment_system"] == params[:id] }
    raise ActiveRecord::RecordNotFound unless @provider
    @distribution = @run&.report&.dig("distribution", params[:id]) || {}
    @volume = @run&.report&.dig("volume_distribution", params[:id]) || {}
    @capacity = @run&.report&.dig("capacity_utilization", params[:id]) || {}
    @performance = @run&.report&.dig("provider_performance", params[:id]) || {}
  end

  private

  def load_run = @run = RoutingRun.where(status: "completed").recent.first
  def example_providers = JSON.parse(Rails.root.join("data/examples/providers.json").read).fetch("providers")
end
