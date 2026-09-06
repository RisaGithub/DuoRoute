# frozen_string_literal: true

module AboutHelper
  def render_document(source)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new,
      tables: true, fenced_code_blocks: true, strikethrough: true, no_intra_emphasis: true)
    fragment = Nokogiri::HTML.fragment(markdown.render(source))

    fragment.css("a[href]").each do |link|
      path, anchor = link["href"].split("#", 2)
      document = AboutController::DOCUMENTS.find { |_key, (_title, file)| path == File.basename(file) }
      if document
        link["href"] = product_document_path(document.first, anchor: anchor)
      elsif path.present? && !path.match?(/\A(?:https?:|mailto:)/i)
        # Repository files have no public route; retain their location as readable text.
        label = Nokogiri::XML::Node.new("code", fragment.document)
        label.content = "#{link.text} (#{path.delete_prefix('../')})"
        link.replace(label)
      end
    end

    seen = Hash.new(0)
    fragment.css("h1, h2, h3, h4, h5, h6").each do |heading|
      slug = heading.text.downcase.gsub(/[^\p{L}\p{N}\p{M}\-_\s]/, "").gsub(/\s/, "-")
      ordinal = seen[slug]
      seen[slug] += 1
      heading["id"] = ordinal.zero? ? slug : "#{slug}-#{ordinal}"
    end

    fragment.css("table").each do |table|
      wrapper = Nokogiri::XML::Node.new("div", fragment.document)
      wrapper["class"] = "product-doc__table"
      wrapper["tabindex"] = "0"
      table.add_previous_sibling(wrapper)
      wrapper.add_child(table)
    end

    sanitize(fragment.to_html,
      tags: %w[a p h1 h2 h3 h4 h5 h6 ul ol li strong em del blockquote pre code hr br table thead tbody tr th td div],
      attributes: %w[href title id class colspan rowspan align start tabindex])
  end
end
