# frozen_string_literal: true

module RubyPreflight
  def self.check!
    required = File.read(File.expand_path("../.ruby-version", __dir__)).strip
    return if RUBY_VERSION == required

    warn "DuoRoute требует Ruby #{required}."
    warn "Сейчас используется Ruby #{RUBY_VERSION}."
    warn "Активируйте rbenv и проверьте: ruby -v"
    exit 1
  end
end
