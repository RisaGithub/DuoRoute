# frozen_string_literal: true

class AboutController < ApplicationController
  DOCUMENTS = {
    "cli" => [ "CLI", "docs/CLI.md" ],
    "web" => [ "Web-интерфейс", "docs/WEB.md" ],
    "criteria_compliance" => [ "Соответствие критериям", "docs/CRITERIA_COMPLIANCE.md" ],
    "architecture" => [ "Архитектура", "docs/ARCHITECTURE.md" ],
    "algorithm" => [ "Алгоритм", "docs/ALGORITHM.md" ]
  }.freeze

  def show
    @strategies = DuoRoute::StrategyCatalog.all
    @demo_run = RoutingRun.where(status: "completed").where(name: "Публичный пример").recent.first || RoutingRun.where(status: "completed").recent.first
    if @demo_run
      decisions = @demo_run.decisions
      @hard_operation = decisions.find { |row| row.fetch("attempts", []).any? { |a| DuoRoute::ReasonCodes::HARD.include?(a["reason"]) } }
      @cascade_operation = decisions.find { |row| row["fallback_used"] || row.fetch("attempts", []).count { |a| a.key?("result") } > 1 }
    end
  end

  def document
    @title, path = DOCUMENTS.fetch(params[:document]) { raise ActionController::RoutingError, "Not Found" }
    @source = Rails.root.join(path).read
  end
end
