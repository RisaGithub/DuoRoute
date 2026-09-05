require "test_helper"

class ExperimentsTest < ActionDispatch::IntegrationTest
  test "strategy tabs show only their own content and keep validation in the active tab" do
    get strategies_path
    assert_response :success
    assert_select ".strategy-tabs a[aria-current='page'][href='#{strategies_path}']", count: 1
    assert_select ".strategy-row", count: 7
    assert_select "#comparison", count: 0

    get compare_strategies_path
    assert_response :success
    assert_select ".strategy-tabs a[aria-current='page'][href='#{compare_strategies_path}']", count: 1
    assert_select "#comparison", count: 1
    assert_select ".strategy-row", count: 0
    assert_select ".comparison-analysis", count: 1

    get compare_strategies_path, params: { seed: 42 }
    assert_response :unprocessable_entity
    assert_select ".strategy-tabs a[aria-current='page'][href='#{compare_strategies_path}']", count: 1
    assert_select ".strategy-row", count: 0
  end

  test "strategy selection navigates within the comparison frame without an anchor" do
    get compare_strategies_path
    assert_response :success
    assert_select "turbo-frame#strategy_comparison:not([autoscroll])", count: 1
    links = css_select(".comparison-option__link[href]")
    assert_equal 7, links.length
    links.each do |link|
      assert_not_includes link["href"], "#"
      assert_equal "true", link["data-turbo"]
      assert_equal "strategy_comparison", link["data-turbo-frame"]
      assert_equal "advance", link["data-turbo-action"]
    end
    link = links.find { |item| item["aria-current"] != "true" }
    get link["href"], headers: { "Turbo-Frame" => "strategy_comparison" }
    assert_response :success
    assert_select "turbo-frame#strategy_comparison .comparison-analysis h3", text: link.css("span").first.text
  end

  test "comparison URL opens directly and GET results survive reload" do
    get compare_strategies_path
    assert_response :success
    assert_select "#comparison form[method='get']"
    assert_select ".comparison-analysis", count: 1
    assert_select ".comparison-results tbody tr", count: 7
    assert_select "input[name='presets[]'][checked]", count: 7

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

  test "default analysis selects the ranked leader and allows another focus" do
    get compare_strategies_path
    assert_response :success
    rows = css_select(".comparison-ranking tbody tr")
    values = rows.map { |row| row.css("td").drop(1).map { |cell| cell.text.tr(",", ".").to_f } }
    assert_equal values.sort_by { |approval, fallback, latency| [ -approval, fallback, latency ] }, values
    assert_select ".comparison-analysis h3", text: rows.first.css("td").first.text
    link = css_select(".comparison-option__link[href]").find { |item| item["aria-current"] != "true" }
    get link["href"]
    assert_response :success
    assert_select ".comparison-analysis h3", text: link.css("span").first.text
    assert_select ".comparison-ranking tbody tr", count: 7
  end

  test "default comparison ignores saved settings while saved comparison uses them" do
    input = { presets: %w[count_share conversion], seed: 42, focus: "count_share" }
    get compare_strategies_path, params: input
    assert_response :success
    default_results = css_select(".comparison-results").first.text
    StrategySetting.create!(name: "count_share", provider_overrides: {
      "vipay" => { "traffic_percentage" => 100 }, "payflow" => { "traffic_percentage" => 0 },
      "quickpay" => { "traffic_percentage" => 0 }
    })
    get compare_strategies_path, params: input
    assert_response :success
    assert_equal default_results, css_select(".comparison-results").first.text
    default_deviations = css_select(".comparison-deviations").first.text
    get compare_strategies_path, params: input.merge(source: "saved")
    assert_response :success
    assert_select ".comparison-analysis .pill", text: "Сохранённые параметры"
    assert_not_equal default_deviations, css_select(".comparison-deviations").first.text
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
