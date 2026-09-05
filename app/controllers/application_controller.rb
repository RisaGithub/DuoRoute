class ApplicationController < ActionController::Base
  private

  def select_completed_run
    @completed_runs = RoutingRun.where(status: "completed").order(completed_at: :desc, id: :desc)
    @run = params[:run_id].present? ? @completed_runs.find(params[:run_id]) : @completed_runs.first
  end

  public

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
