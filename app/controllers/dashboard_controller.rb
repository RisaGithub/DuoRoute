# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    select_completed_run
  end
end
