# frozen_string_literal: true

class AnalyticsController < ApplicationController
  def show
    @runs = RoutingRun.where(status: "completed").recent.limit(20)
    @run = @runs.first
    history = DuoRoute::Input::Loader.csv_file(Rails.root.join("data/examples/operations_history.csv").to_s)
    @history_analytics = DuoRoute::Reporting::HistoryAnalyzer.new(history).call
  end
end
