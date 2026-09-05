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
  end

  def document
    @title, path = DOCUMENTS.fetch(params[:document]) { raise ActionController::RoutingError, "Not Found" }
    @source = Rails.root.join(path).read
  end
end
