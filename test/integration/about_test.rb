# frozen_string_literal: true

require "test_helper"

class AboutTest < ActionDispatch::IntegrationTest
  test "public presentation links to the console and current strategy catalog" do
    get about_path
    assert_response :success
    assert_select "html[lang=ru]"
    assert_select "h1", /объяснимый маршрут/
    assert_select ".nav__link--active[aria-current=page][href=?]", about_path
    assert_select ".product-hero a[href=?]", new_run_path
    assert_select ".product-strategy", count: DuoRoute::StrategyCatalog.all.size
    DuoRoute::StrategyCatalog.all.each_key do |name|
      assert_select ".product-strategy code", text: name
    end
    document = Nokogiri::HTML(response.body)
    document.css('.product a[href^="#"]').each do |link|
      assert document.at_css("[id='#{link['href'].delete_prefix('#')}']"), "Missing anchor: #{link['href']}"
    end
    assert_select "[data-controller=clipboard]", count: 5
  end

  test "documentation serves only allowlisted repository documents as escaped text" do
    assert_equal %w[cli web criteria_compliance architecture algorithm], AboutController::DOCUMENTS.keys
    AboutController::DOCUMENTS.each do |name, (_title, path)|
      get product_document_path(name)
      assert_response :success
      assert_equal Rails.root.join(path).read, Nokogiri::HTML(response.body).at_css(".product-doc pre").text
    end
    %w[credentials readme formats final ../README.md %2e%2e%2fconfig/master.key].each do |name|
      get product_document_path(name)
      assert_response :not_found
    end
    get about_path
    links = Nokogiri::HTML(response.body).css(".product-doc-links a").map { |link| link["href"] }
    assert_equal AboutController::DOCUMENTS.keys.map { |name| product_document_path(name) }, links
    Nokogiri::HTML(response.body).css('a[href^="/about/docs/"]').each do |link|
      get link["href"]
      assert_response :success
    end
  end

  test "public JSON excerpts agree with a fresh scripted demo" do
    result = DuoRoute::Runner.new(
      providers_data: DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/providers.json")),
      operations: DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/operations_queue_10.json")),
      config: DuoRoute::Input::Loader.config_file(Rails.root.join("config/routing/default.yml")),
      history: DuoRoute::Input::Loader.csv_file(Rails.root.join("data/examples/operations_history.csv")),
      outcomes: DuoRoute::Input::Loader.json_file(Rails.root.join("data/examples/demo_outcomes.json")),
      preset: "balanced", seed: 42
    ).call
    get about_path
    examples = Nokogiri::HTML(response.body).css(".product-outputs pre code").map { |node| JSON.parse(node.text) }
    decision = result.decisions.find { |row| row["operation_id"] == "op_105" }
    assert_equal decision.slice(*examples.first.first.keys), examples.first.first
    assert_equal result.report.slice(*examples.last.keys), examples.last
    assert_equal "bank_not_in_list", decision["attempts"].find { |row| row["provider"] == "payflow" }["reason"]
    vipay = decision["attempts"].find { |row| row["provider"] == "vipay" }
    assert_equal "expired", vipay["result"]
    assert_select ".product-decision__row b", text: vipay["score"].to_s
  end
end
