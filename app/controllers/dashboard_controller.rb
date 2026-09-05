# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @run = RoutingRun.where(status: "completed").recent.first
    @recent_runs = RoutingRun.recent.limit(6)
  end
end
