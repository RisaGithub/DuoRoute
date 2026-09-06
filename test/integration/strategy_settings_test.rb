require "test_helper"

class StrategySettingsTest < ActionDispatch::IntegrationTest
  test "list exposes defaults and saves them for new runs without JavaScript" do
    get strategies_path
    assert_response :success
    assert_select ".strategy-row", count: 7
    assert_select "#count_share_vipay_traffic_percentage[value='40']"
    overrides = { vipay: { traffic_percentage: "45" }, payflow: { traffic_percentage: "30" }, quickpay: { traffic_percentage: "25" } }
    patch strategy_settings_path(name: "count_share"), params: { provider_overrides: overrides }
    assert_redirected_to strategies_path(anchor: "count_share")
    get new_run_path(preset: "count_share")
    assert_response :success
    assert_select "textarea[name='settings']", /vipay.traffic_percentage=45.0/
    post runs_path, params: { preset: "count_share", config_text: "{}", simulator_mode: "provider_snapshot" }
    assert_response :redirect
    run = RoutingRun.order(:id).last
    assert_equal 45.0, run.config.dig("provider_overrides", "vipay", "traffic_percentage")
    post compare_strategies_path, params: { presets: [ "count_share", "amount_range" ] }
    assert_response :success
    delete reset_strategy_settings_path(name: "count_share")
    assert_redirected_to strategies_path(anchor: "count_share")
    assert_equal 40, StrategySetting.catalog.dig("count_share", "parameters", "provider_overrides", "vipay", "traffic_percentage")
    assert_equal 45.0, run.reload.config.dig("provider_overrides", "vipay", "traffic_percentage")
  end

  test "invalid shares and ranges do not persist and preserve input" do
    overrides = DuoRoute::StrategyCatalog.all.dig("count_share", "parameters", "provider_overrides")
    overrides["vipay"]["traffic_percentage"] = "90"
    patch strategy_settings_path(name: "count_share"), params: { provider_overrides: overrides }
    assert_response :unprocessable_entity
    assert_select ".alert--error", /Сумма долей/
    assert_select "#count_share_vipay_traffic_percentage[value='90.0']"
    assert_nil StrategySetting.find_by(name: "count_share")
    overrides = DuoRoute::StrategyCatalog.all.dig("amount_range", "parameters", "provider_overrides")
    overrides["payflow"]["preferred_amount_min"] = 60000
    patch strategy_settings_path(name: "amount_range"), params: { provider_overrides: overrides }
    assert_response :unprocessable_entity
    assert_select ".alert--error", /нижняя граница/
    assert_nil StrategySetting.find_by(name: "amount_range")
  end

  test "volume settings accept missing partial and explicit zero targets" do
    get strategies_path
    assert_select "#volume_share_vipay_volume_share_pct[required]", count: 0
    assert_select "#volume_share_vipay_volume_share_pct[placeholder='не задано']"
    [ [ "", "", "" ], [ "0", "", "" ], [ "40", "", "" ], [ "40", "30", "30" ] ].each do |values|
      overrides = %w[vipay payflow quickpay].zip(values).to_h.transform_values { |value| { volume_share_pct: value } }
      patch strategy_settings_path(name: "volume_share"), params: { provider_overrides: overrides }
      assert_response :redirect
      actual = StrategySetting.find_by!(name: "volume_share").provider_overrides.values.map { |row| row["volume_share_pct"] }
      assert_equal values.map { |value| value.empty? ? nil : value.to_f }, actual
    end
  end

  test "nullable maximum and explicit per-run overrides are respected" do
    overrides = DuoRoute::StrategyCatalog.all.dig("amount_range", "parameters", "provider_overrides")
    overrides["quickpay"]["preferred_amount_max"] = ""
    patch strategy_settings_path(name: "amount_range"), params: { provider_overrides: overrides }
    assert_response :redirect
    assert_nil StrategySetting.find_by!(name: "amount_range").provider_overrides.dig("quickpay", "preferred_amount_max")
    config = StrategySetting.apply({ "provider_overrides" => { "payflow" => { "preferred_amount_min" => 700 } } }, "amount_range")
    assert_equal 700, config.dig("provider_overrides", "payflow", "preferred_amount_min")
  end
end
