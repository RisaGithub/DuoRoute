#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "pathname"

# Scan shipped documentation and text-bearing application sources, including comments.
class ProductionDocsCheck
  ROOT = File.expand_path("..", __dir__)
  GLOBS = %w[CHANGELOG.md README.md THIRD_PARTY_NOTICES.md docs/**/*.{md,txt,html} app/views/**/* app/helpers/**/*.rb
    app/controllers/**/*.rb app/models/**/*.rb app/javascript/**/*.{js,json} app/assets/stylesheets/*.css
    config/locales/**/* config/routing/**/*.{yml,yaml,json} data/examples/**/*.{yml,yaml,json}
    schemas/**/*.json lib/*.rb lib/duo_route/**/*.rb].freeze
  RULES = {
    /telegram|t\.me\/|телеграм|discord(?:app)?\.com\/channels\/|slack\.com\/archives\//iu => "internal chat reference",
    /\bzoom\b|расшифровк[аиу].{0,30}конференц/iu => "internal conference reference",
    /\bQA(?:[_-]zoom)?\b|answers(?:_\d+)?\.txt|checkpoint|чекпо[ий]нт/iu => "internal question file or checkpoint",
    %r{/(?:Volumes|Users|home|private/tmp|var/folders)/[^\s<>"']+}i => "absolute workstation path",
    /\b(?:\u0043odex|\u0043hatGPT)\b|(?<![\p{L}])\u0418\u0418(?![\p{L}])|\bAI[- ](?:generated|assisted)\b|генераци[яи] кода/iu => "generation attribution",
    /(?:№\s*\d+|\bmessages?\s*(?:\#|№)?\s*\d+|сообщени[еяй]\s*(?:\#|№)?\s*\d+)/iu => "internal message number",
    /(?:организатор.{0,35}(?:ответил|подтвердил).{0,20}чат|на конференции нам сказали|переписк[аи]|\bTODO\b|\bFIXME\b)/iu => "internal discussion or unfinished note"
  }.freeze

  attr_reader :errors

  def initialize(root = ROOT)
    @root = File.expand_path(root)
    @errors = []
  end

  def files
    GLOBS.flat_map { |glob| Dir.glob(File.join(@root, glob)) }.select { |path| File.file?(path) }.uniq.sort
  end

  def check
    @errors.clear
    files.each { |file| check_text(file, File.read(file)) }
    @errors
  end

  def check_text(file, content)
    content.each_line.with_index(1) do |line, number|
      RULES.each { |pattern, reason| violation(file, number, reason) if line.match?(pattern) }
      targets = line.scan(/\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)/).flatten
      targets += line.scan(/^\s{0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)/).flatten
      targets += line.scan(/(?:href|src)=["']([^"'<>]+)["']/).flatten
      targets.each { |target| check_link(file, number, target) }
    end
  end

  private

  def violation(file, number, reason)
    relative = Pathname(file).relative_path_from(Pathname(@root))
    @errors << "#{relative}:#{number}: #{reason}"
  end

  def check_link(file, number, target)
    target = CGI.unescapeHTML(target.delete_prefix("<").delete_suffix(">"))
    return if target.match?(/\A(?:https?:|mailto:|#)/i)
    return if target.include?("<%")
    if target.match?(/\A(?:[a-z][a-z0-9+.-]*:|\/\/)/i)
      violation(file, number, "unsupported local link: #{target}")
      return
    end
    # Root-relative Web routes are checked against the running app by integration tests.
    return if target.start_with?("/") && File.extname(file) != ".md"
    path = CGI.unescapeURIComponent(target.split(/[?#]/, 2).first.to_s)
    resolved = File.expand_path(path, File.dirname(file))
    if !resolved.start_with?("#{@root}/") && resolved != @root
      violation(file, number, "link outside repository: #{target}")
    elsif !File.exist?(resolved)
      violation(file, number, "missing local file: #{target}")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  check = ProductionDocsCheck.new
  errors = check.check
  if errors.any?
    warn errors.join("\n")
    exit 1
  end
  puts "Production documentation: #{check.files.length} files, 0 errors"
end
