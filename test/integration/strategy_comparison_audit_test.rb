require "test_helper"

class StrategyComparisonAuditTest < ActionDispatch::IntegrationTest
  test "every strategy and selected panel match independently audited decisions across seeds and sources" do
    catalog = DuoRoute::StrategyCatalog.all
    saved = JSON.parse(JSON.generate(catalog))
    saved["count_share"]["parameters"]["provider_overrides"].each_with_index { |(_, fields), i| fields["traffic_percentage"] = [ 100, 0, 0 ][i] }
    saved["volume_share"]["parameters"]["provider_overrides"].each_with_index { |(_, fields), i| fields["volume_share_pct"] = [ 20, 30, 50 ][i] }
    saved["cascade"]["parameters"]["provider_overrides"].each_with_index { |(_, fields), i| fields["priority"] = 3 - i }
    saved["amount_range"]["parameters"]["provider_overrides"].each_value { |fields| fields.merge!("preferred_amount_min" => 0, "preferred_amount_max" => 200000) }
    saved["intensity"]["parameters"]["provider_overrides"].each_value { |fields| fields["requests_per_minute_limit"] = 1 }
    saved["turnover_commitment"]["parameters"]["provider_overrides"].each_value { |fields| fields.transform_values! { 4000000 } }
    saved.each do |name, entry|
      next if entry["parameters"]["provider_overrides"].empty?
      StrategySetting.create!(name:, provider_overrides: entry["parameters"]["provider_overrides"])
    end

    providers = JSON.parse(Rails.root.join("data/examples/providers.json").read)
    operations = JSON.parse(Rails.root.join("data/examples/operations_queue_10.json").read)
    original = JSON.generate([ providers, operations ])
    { "defaults" => catalog, "saved" => saved }.each do |source, entries|
      [ 0, 17, 42 ].each do |seed|
        expected = entries.to_h do |name, entry|
          config = DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml").to_s)
          config["simulation"]["source"] = "provider_snapshot"
          config["provider_overrides"] = entry["parameters"]["provider_overrides"]
          runner = DuoRoute::Runner.new(providers_data: providers, operations:, config:, preset: name, seed:)
          result = runner.call
          decisions = result.decisions
          report = result.report
          assert_equal entry["weights"], runner.config.dig("presets", name, "weights")
          assert decisions.all? { |d| d["strategy"] == name }
          decisions.each do |decision|
            assert_equal decision["attempts"].sum { |attempt| attempt.fetch("latency_sec", 0) }, decision["latency_sec"]
            assert_equal decision["selected_provider"] == "spacepayments", decision["fallback_used"]
            assert decision.dig("constraint_matrix", decision["selected_provider"], "eligible")
          end
          assert_equal (decisions.count { |d| d["simulated_result"] == "approved" } * 100.0 / operations.length).round(2), report["approval_rate_pct"]
          assert_equal (decisions.count { |d| d["selected_provider"] == "spacepayments" } * 100.0 / operations.length).round(2), report["fallback_rate_pct"]
          assert_equal (decisions.sum { |d| d["latency_sec"] }.to_f / operations.length).round(2), report["average_latency_sec"]
          runner.providers_data["providers"].each do |provider|
            routed = decisions.select { |d| d["selected_provider"] == provider["payment_system"] }
            count_share = (routed.length * 100.0 / operations.length).round(2)
            assert_equal (count_share - provider["traffic_percentage"]).round(2), report.dig("distribution", provider["payment_system"], "deviation_pp")
            volume = routed.sum { |d| operations.find { |op| op["operation_id"] == d["operation_id"] }["amount"] }
            volume_share = (volume * 100.0 / operations.sum { |op| op["amount"] }).round(2)
            actual = report.dig("volume_distribution", provider["payment_system"], "deviation_pp")
            if provider["volume_share_pct"].nil?
              assert_nil actual
            else
              assert_equal (volume_share - provider["volume_share_pct"]).round(2), actual
            end
          end
          [ name, report ]
        end
        assert_equal original, JSON.generate([ providers, operations ]), "Runs must not mutate shared input"
        get compare_strategies_path, params: { presets: entries.keys, source:, seed: }
        assert_response :success
        links = css_select(".comparison-option__link[href]").to_h { |link| [ Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)["focus"], link["href"] ] }
        expected.each do |name, report|
          get links.fetch(name), headers: { "Turbo-Frame" => "strategy_comparison" }
          assert_response :success
          assert_select ".comparison-analysis[data-strategy='#{name}'] h3", text: entries[name]["title"]
          assert_equal 1, css_select(".comparison-option--active").length
          assert_equal 1, css_select(".comparison-option__link[aria-current='true']").length
          assert_select ".comparison-ranking__active td:first-child", text: entries[name]["title"]
          metrics = css_select(".comparison-kpis strong").map { |item| item.text.tr(",", ".").to_f }
          assert_equal report.values_at("approval_rate_pct", "fallback_rate_pct", "average_latency_sec"), metrics
          assert_select "input[name='seed'][value='#{seed}']"
          assert_select "select[name='source'] option[value='#{source}'][selected]"
          assert_select "input[name='presets[]'][checked]", count: 7
          css_select(".comparison-ranking tbody tr").each do |row|
            key = entries.find { |_, entry| entry["title"] == row.css("td").first.text }.first
            assert_equal expected[key].values_at("approval_rate_pct", "fallback_rate_pct", "average_latency_sec"), row.css("td").drop(1).map { |cell| cell.text.tr(",", ".").to_f }
          end
          expected_deviations = %w[distribution volume_distribution].map do |metric|
            values = report[metric].values.filter_map { |row| row["deviation_pp"] }
            values.empty? ? "цель не задана" : "#{values.sum(&:abs).round(1)} п.п."
          end
          assert_equal expected_deviations, css_select(".comparison-deviations b").map(&:text)
        end
      end
    end
  end

  test "excluded and unknown focus fall back to the leader without stale analysis" do
    %w[intensity unknown].each do |focus|
      get compare_strategies_path, params: { presets: %w[count_share volume_share], source: "saved", seed: 17, focus: }, headers: { "Turbo-Frame" => "strategy_comparison" }
      assert_response :success
      assert_select ".comparison-ranking tbody tr", count: 2
      assert_select ".comparison-analysis h3", text: css_select(".comparison-ranking tbody tr td").first.text
      assert_select "input[name='presets[]'][checked]", count: 2
    end
  end
end
