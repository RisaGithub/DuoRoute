# frozen_string_literal: true

class AboutController < ApplicationController
  DOCUMENTS = {
    "readme" => [ "Руководство DuoRoute", "README.md" ],
    "algorithm" => [ "Алгоритм маршрутизации", "docs/ALGORITHM.md" ],
    "formats" => [ "Входные и выходные форматы", "docs/INPUT_OUTPUT.md" ],
    "final" => [ "Финальная очередь", "docs/STOPCODE_CHECKLIST.md" ]
  }.freeze

  def show
    @strategies = DuoRoute::StrategyCatalog.all
  end

  def document
    @title, path = DOCUMENTS.fetch(params[:document]) { raise ActionController::RoutingError, "Not Found" }
    @source = Rails.root.join(path).read
  end
end
