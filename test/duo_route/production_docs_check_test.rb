require "test_helper"
require_relative "../../script/check_production_docs"

class ProductionDocsCheckTest < ActiveSupport::TestCase
  test "rejects internal references and workstation paths" do
    [ "Telegram №253", "/Volumes/SSD/project/README.md", "[notes](../QA/answers_1.txt)",
      "QA_zoom", "Zoom transcript", "message 253", "checkpoint", "t.me/channel/253" ].each do |text|
      check = ProductionDocsCheck.new
      check.check_text(File.join(ProductionDocsCheck::ROOT, "README.md"), text)
      assert check.errors.any?, text
      assert_match(/README.md:1:/, check.errors.first)
    end
  end

  test "allows technical versions dates numbers and percentages" do
    check = ProductionDocsCheck.new
    check.check_text(File.join(ProductionDocsCheck::ROOT, "README.md"),
      "Version 1.0, snapshot_at 2026-09-06T12:00:00Z, 253 operations, 99.5%, RPM 100")
    assert_empty check.errors
  end

  test "discovers Web text and CLI sources while excluding test fixtures" do
    Dir.mktmpdir do |root|
      %w[app/views/about/show.html.erb app/helpers/label_helper.rb lib/duo_route/cli/app.rb test/example.rb].each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), "<p>Telegram</p>\n")
      end
      check = ProductionDocsCheck.new(root)
      assert_equal 3, check.check.length
      assert check.errors.any? { |error| error.start_with?("app/views/about/show.html.erb:1:") }
      assert check.errors.none? { |error| error.start_with?("test/") }
    end
  end

  test "checks missing escaped reference and HTML local links and repository boundary" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "present.md"), "# Present")
      check = ProductionDocsCheck.new(root)
      check.check_text(File.join(root, "README.md"), <<~MARKDOWN)
        [valid](present.md#present)
        [missing](missing.md)
        [ref]: absent.md
        <a href="lost.md">Lost</a>
        [outside](../outside.md)
        [escaped](missing%20file.md)
        [remote](https://example.org)
      MARKDOWN
      assert_equal 5, check.errors.length
      assert_match(/README.md:2: missing local file/, check.errors.first)
      assert check.errors.any? { |error| error.include?("outside repository") }
    end
  end

  test "command returns a nonzero status with file line and reason" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "script"))
      FileUtils.cp(File.join(ProductionDocsCheck::ROOT, "script/check_production_docs.rb"), File.join(root, "script"))
      File.write(File.join(root, "README.md"), "# Product\nTelegram message 253\n")
      output, status = Open3.capture2e(RbConfig.ruby, File.join(root, "script/check_production_docs.rb"))
      assert_equal 1, status.exitstatus
      assert_includes output, "README.md:2: internal chat reference"
    end
  end

  test "shipped production documentation passes" do
    assert_empty ProductionDocsCheck.new.check
  end
end
