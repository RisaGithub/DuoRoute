# frozen_string_literal: true

class ProvidersController < ApplicationController
  before_action :select_completed_run

  def index
    @providers = @run ? @run.providers.fetch("providers", []) : []
  end

  def show
    @provider = (@run ? @run.providers.fetch("providers", []) : [])
      .find { |provider| provider["payment_system"] == params[:id] }
    raise ActiveRecord::RecordNotFound unless @provider
    @distribution = @run&.report&.dig("distribution", params[:id]) || {}
    @volume = @run&.report&.dig("volume_distribution", params[:id]) || {}
    @capacity = @run&.report&.dig("capacity_utilization", params[:id]) || {}
    @performance = @run&.report&.dig("provider_performance", params[:id]) || {}
  end
end
