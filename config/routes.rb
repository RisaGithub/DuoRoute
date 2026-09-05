Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "dashboard#show"

  resources :runs, controller: "routing_runs", only: %i[index new create show] do
    member do
      get :progress
      get "operations/:operation_id", action: :operation, as: :operation
      get "download/:artifact", action: :download, as: :download
      get "preview/:artifact", action: :preview, as: :preview
    end
  end
  resources :providers, only: %i[index show]
  get "strategies", to: "strategies#show"
  post "strategies/compare", to: "strategies#compare", as: :compare_strategies
  get "generator", to: "generators#show"
  post "generator", to: "generators#create"
end
