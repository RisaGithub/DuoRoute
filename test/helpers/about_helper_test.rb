require "test_helper"

class AboutHelperTest < ActionView::TestCase
  test "rendered Markdown preserves anchors and code while removing unsafe HTML" do
    source = <<~MARKDOWN
      <a id="section"></a>
      ## Section
      <script>alert('unsafe')</script>
      <a href="javascript:alert(1)" onclick="alert(1)">Unsafe link</a>

      ```html
      <script>example()</script>
      ```
    MARKDOWN

    document = Nokogiri::HTML.fragment(render_document(source))
    assert document.at_css("#section")
    assert_equal "Section", document.at_css("h2").text
    assert_nil document.at_css("script, [onclick], [href^='javascript:']")
    assert_equal "<script>example()</script>\n", document.at_css("pre code").text
  end
  test "document navigation preserves local anchors without broken repository URLs" do
    document = Nokogiri::HTML.fragment(render_document(<<~MARKDOWN))
      ## Section
      ## Section
      [CLI](CLI.md#commands)
      [Local](#section)
      [Source](../lib/duo_route/engine.rb)
      [External](https://example.org)
    MARKDOWN
    assert document.at_css("#section")
    assert document.at_css("#section-1")
    assert document.at_css('a[href="/about/docs/cli#commands"]')
    assert document.at_css('a[href="#section"]')
    assert_nil document.at_css('a[href^="../"]')
    assert_includes document.text, "lib/duo_route/engine.rb"
    assert document.at_css('a[href="https://example.org"]')
  end
end
