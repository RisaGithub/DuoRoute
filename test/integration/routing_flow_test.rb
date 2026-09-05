# frozen_string_literal: true

require "test_helper"

class RoutingFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    RoutingRun.delete_all
  end

  test "dashboard new run background progress detail and downloads" do
    get root_path
    assert_response :success
    assert_select "h1", /Операционная картина/
    get new_run_path
    assert_response :success
    assert_select "form"

    assert_enqueued_with(job: RoutingRunJob) do
      post runs_path, params: {
        name: "Integration run", preset: "balanced", timeout_mode: "fallback_on_timeout", simulator_mode: "scripted", seed: 42,
        providers_text: Rails.root.join("data/examples/providers.json").read,
        operations_text: Rails.root.join("data/examples/operations_queue_10.json").read,
        config_text: Rails.root.join("config/routing/default.yml").read,
        history_text: Rails.root.join("data/examples/operations_history.csv").read,
        outcomes_text: Rails.root.join("data/examples/demo_outcomes.json").read
      }
    end
    run = RoutingRun.find_by!(name: "Integration run")
    assert_redirected_to run_path(run)
    perform_enqueued_jobs
    run.reload
    assert_equal "completed", run.status

    get run_path(run)
    assert_response :success
    %w[decisions report config manifest providers operations history outcomes].each do |artifact|
      assert_select ".artifact-actions" do
        assert_select "button[aria-controls='preview-#{run.id}-#{artifact}']", count: 1
        assert_select "dialog#preview-#{run.id}-#{artifact}", count: 1
        assert_select "a[href='#{download_run_path(run, artifact)}']", count: 2
      end
    end

    %w[decisions report config manifest providers operations history outcomes].each do |artifact|
      get download_run_path(run, artifact)
      assert_response :success
      assert_match(/attachment/, response.headers["Content-Disposition"])
      original = response.body

      get preview_run_path(run, artifact, format: :json)
      assert_response :success
      data = response.parsed_body
      assert data["filename"].present?
      assert_equal artifact == "history" ? original : JSON.pretty_generate(JSON.parse(original)), data["content"]

      get preview_run_path(run, artifact)
      assert_response :success
      assert_equal "text/html", response.media_type
      assert_nil response.headers["Content-Disposition"]
      displayed = Nokogiri::HTML(response.body).at_css(".artifact-preview pre code").text
      if artifact == "history"
        assert_equal original, displayed
      else
        assert_equal JSON.parse(original), JSON.parse(displayed)
      end
    end

    run.update!(history_csv: "<script>alert('preview')</script>")
    get preview_run_path(run, "history")
    assert_select ".artifact-preview script", count: 0
    assert_select ".artifact-preview code", text: run.history_csv

    get preview_run_path(run, "unknown")
    assert_response :not_found

    run.update!(history_csv: "")
    get preview_run_path(run, "history")
    assert_response :success
    assert_select ".artifact-preview .empty"

    get progress_run_path(run)
    assert_response :success
    assert_equal "completed", response.parsed_body["status"]
    get operation_run_path(run, run.decisions.first["operation_id"])
    assert_response :success
    assert_select "h1", /Почему выбран/
    assert_select ".timeline__item"
    get download_run_path(run, "decisions")
    assert_response :success
    assert_equal run.total, response.parsed_body.length
  end

  test "invalid manual input renders all validator errors without creating run" do
    assert_no_difference("RoutingRun.count") do
      post runs_path, params: { preset: "balanced", timeout_mode: "fallback_on_timeout", simulator_mode: "seeded", seed: 42,
        providers_text: "{}", operations_text: "[]", config_text: "{}" }
    end
    assert_response :unprocessable_entity
    assert_select ".alert--error li", minimum: 2
  end

  test "supporting pages render" do
    [ runs_path, providers_path, strategies_path, generator_path ].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "navigation marks the current section on root and nested pages" do
    { root_path => root_path, new_run_path => runs_path, providers_path => providers_path,
      strategies_path => strategies_path,
      generator_path => generator_path }.each do |path, active_path|
      get path
      assert_response :success, path
      assert_select ".nav__link--active[aria-current='page'][href='#{active_path}']", count: 1
      assert_select ".nav__link--active", count: 1
    end
  end

  test "dashboard names and timestamps the latest completed run" do
    finished_at = Time.zone.local(2026, 9, 4, 21, 29)
    RoutingRun.create!(name: "Latest snapshot", status: "completed", preset: "balanced",
      timeout_mode: "fallback_on_timeout", simulator_mode: "seeded", seed: 42,
      providers_json: '{"providers":[]}', operations_json: "[]", config_json: "{}",
      report_json: '{"total_operations":0,"total_amount":0,"approval_rate_pct":0,"fallback_rate_pct":0,"average_latency_sec":0,"target_exceptions":[],"distribution":{},"skip_reasons":{},"capacity_utilization":{}}',
      completed_at: finished_at)

    get root_path

    assert_response :success
    assert_select ".page-head .eyebrow", text: "Данные выбранного завершённого запуска"
    assert_select ".page-head h1", text: "Запуск · Latest snapshot"
    assert_select ".page-head__sub", /Завершён 04\.09\.2026 в 21:29/
  end
end
