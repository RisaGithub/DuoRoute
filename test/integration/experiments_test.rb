require "test_helper"

class ExperimentsTest < ActionDispatch::IntegrationTest
  test "comparison URL opens directly and GET results survive reload" do
    get compare_strategies_path
    assert_response :success
    assert_select "#comparison form[method='get']"
    assert_select ".comparison-results", count: 0
    assert_select "input[name='presets[]'][checked]", count: 3

    url = compare_strategies_path(presets: %w[cascade conversion], seed: 17)
    get url
    assert_response :success
    assert_select ".comparison-results tbody tr", count: 2
    rows = css_select(".comparison-results tbody").first.text
    get url
    assert_response :success
    assert_equal rows, css_select(".comparison-results tbody").first.text
    assert_select "input[name='seed'][value='17']"
    assert_select "input[name='presets[]'][checked]", count: 2

    get compare_strategies_path, params: { seed: 17 }
    assert_response :unprocessable_entity
    assert_select "input[name='presets[]'][checked]", count: 0
  end

  test "comparison requires two strategies and keeps submitted selection" do
    post compare_strategies_path, params: { presets: [ "cascade" ], seed: 17 }
    assert_response :unprocessable_entity
    assert_select "input[name='presets[]'][checked]", count: 1
    assert_select "input[value='cascade'][checked]"
    post compare_strategies_path, params: { presets: %w[cascade conversion], seed: "oops" }
    assert_response :unprocessable_entity
    post compare_strategies_path, params: { presets: %w[cascade conversion], seed: 17 }
    assert_response :success
    assert_select ".comparison-results tbody tr", count: 2
    assert_select ".metric-best", minimum: 1
    assert_select "input[name='seed'][value='17']"
  end

  test "generator preserves input errors and rejects oversized requests" do
    [ 0, 20001, "abc", "1.5" ].each do |count|
      post generator_path, params: { scenario: "normal", operations: count, providers: 4, seed: 42, commit_action: "preview" }
      assert_response :unprocessable_entity
      assert_select "input[name='operations'][value='#{count}']"
    end
    post generator_path, params: { scenario: "normal", operations: 10, providers: 0, seed: 42 }
    assert_response :unprocessable_entity
  end

  test "preview and download include reproducible data and history" do
    input = { scenario: "normal", operations: 8, providers: 3, seed: 17 }
    post generator_path, params: input.merge(commit_action: "preview")
    assert_response :success
    assert_select ".generator-result tbody tr", count: 5
    post generator_path, params: input.merge(commit_action: "download")
    assert_response :success
    bundle = response.parsed_body
    assert_equal 8, bundle["operations"].length
    assert_equal 4, bundle["providers"]["providers"].length
    assert_equal 8, bundle["history"].length
    post generator_path, params: input.merge(commit_action: "download")
    assert_equal bundle, response.parsed_body
  end

  test "invalid scenario can be previewed but never creates a run" do
    input = { scenario: "invalid_data", operations: 10, providers: 3, seed: 42 }
    post generator_path, params: input.merge(commit_action: "preview")
    assert_response :success
    assert_no_difference("RoutingRun.count") do
      post generator_path, params: input.merge(commit_action: "run")
    end
    assert_response :unprocessable_entity
    assert_select ".alert--error"
  end

  test "valid generated data creates a scripted run" do
    assert_difference("RoutingRun.count", 1) do
      post generator_path, params: { scenario: "timeouts", operations: 10, providers: 3, seed: 42, commit_action: "run" }
    end
    assert_response :redirect
    assert_equal "scripted", RoutingRun.order(:id).last.simulator_mode
  end
end
