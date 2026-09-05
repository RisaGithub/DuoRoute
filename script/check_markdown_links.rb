#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "open3"
require "pathname"

# Check repository Markdown only; generated files in tmp/vendor are not documentation.
root = File.expand_path("..", __dir__)
tracked, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "*.md", chdir: root)
abort "Cannot list repository Markdown" unless status.success?
files = tracked.split("\0").uniq.map { |path| File.join(root, path) }.select { |path| File.file?(path) }

def prose(path)
  File.read(path).gsub(/^\s*(`{3,}|~{3,})[^\n]*\n.*?^\s*\1\s*$/m, "")
end

def anchors(path)
  content = prose(path)
  explicit = content.scan(/\b(?:id|name)=["']([^"']+)["']/).flatten
  seen = Hash.new(0)
  headings = content.scan(/^\#{1,6}\s+(.+?)\s*#*$/).flatten.map do |heading|
    slug = heading.downcase.gsub(/<[^>]+>/, "").gsub(/[^\p{L}\p{N}\p{M}\-_\s]/, "").gsub(/\s/, "-")
    ordinal = seen[slug]
    seen[slug] += 1
    ordinal.zero? ? slug : "#{slug}-#{ordinal}"
  end
  explicit + headings
end

errors = []
checked = 0
files.each do |file|
  content = prose(file)
  definitions = content.scan(/^\s{0,3}\[([^\]]+)\]:\s*(<[^>]+>|\S+)/).to_h.transform_keys(&:downcase)
  inline = content.scan(/\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+["'][^\n]*?["'])?\s*\)/).flatten
  references = content.scan(/\[([^\]\n]+)\]\[([^\]\n]*)\]/).map do |label, reference|
    key = (reference.empty? ? label : reference).downcase
    errors << "#{Pathname(file).relative_path_from(Pathname(root))}: undefined reference #{key}" unless definitions.key?(key)
    definitions[key]
  end
  (inline + definitions.values + references.compact).each do |target|
    target = CGI.unescapeHTML(target.delete_prefix("<").delete_suffix(">"))
    next if target.match?(/\A(?:[a-z][a-z0-9+.-]*:|\/\/)/i)

    path, fragment = target.split("#", 2)
    path = path.split("?", 2).first.to_s
    resolved = path.empty? ? file : File.expand_path(CGI.unescapeURIComponent(path), File.dirname(file))
    checked += 1
    if !File.exist?(resolved)
      errors << "#{Pathname(file).relative_path_from(Pathname(root))}: missing #{target}"
    elsif fragment && !fragment.empty? && File.extname(resolved).downcase == ".md" && !anchors(resolved).include?(CGI.unescapeURIComponent(fragment))
      errors << "#{Pathname(file).relative_path_from(Pathname(root))}: missing anchor #{target}"
    end
  end
end
abort errors.join("\n") unless errors.empty?
puts "Markdown: #{files.length} files, #{checked} local links/anchors checked, 0 errors"
