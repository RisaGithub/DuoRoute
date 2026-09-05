# frozen_string_literal: true

module DuoRoute
  module Input
    class Loader
      MAX_BYTES = 128 * 1024 * 1024

      class << self
        def json_file(path)
          parse_json(read(path), path)
        end

        def json_string(content, label: "input")
          ensure_size!(content, label)
          parse_json(content, label)
        end

        def config_file(path)
          content = read(path)
          case File.extname(path).downcase
          when ".json" then parse_json(content, path)
          when ".yml", ".yaml" then parse_yaml(content, path)
          else raise InputError, [ issue(path, "unsupported_format", "ожидается JSON, YAML или YML") ]
          end
        end

        def config_string(content, label: "config.yml", format: :yaml)
          ensure_size!(content, label)
          format.to_sym == :json ? parse_json(content, label) : parse_yaml(content, label)
        end

        def csv_file(path)
          parse_csv(read(path), path)
        end

        def csv_string(content, label: "history.csv")
          ensure_size!(content, label)
          parse_csv(content, label)
        end

        private

        def read(path)
          raise InputError, [ issue(path, "file_not_found", "файл не найден") ] unless File.file?(path)
          raise InputError, [ issue(path, "file_too_large", "файл больше #{MAX_BYTES} байт") ] if File.size(path) > MAX_BYTES

          File.read(path, encoding: "UTF-8")
        rescue Encoding::InvalidByteSequenceError
          raise InputError, [ issue(path, "invalid_encoding", "ожидается UTF-8") ]
        end

        def ensure_size!(content, label)
          raise InputError, [ issue(label, "file_too_large", "данные больше #{MAX_BYTES} байт") ] if content.bytesize > MAX_BYTES
        end

        def parse_json(content, label)
          JSON.parse(content)
        rescue JSON::ParserError => e
          raise InputError, [ issue(label, "malformed_json", e.message) ]
        end

        def parse_yaml(content, label)
          value = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
          value || {}
        rescue Psych::Exception => e
          raise InputError, [ issue(label, "malformed_yaml", e.message) ]
        end

        def parse_csv(content, label)
          CSV.parse(content, headers: true).map.with_index(2) do |row, line|
            raise CSV::MalformedCSVError, "пустое имя столбца, строка #{line}" if row.headers.any?(&:nil?)

            row.to_h.merge("_line" => line)
          end
        rescue CSV::MalformedCSVError => e
          raise InputError, [ issue(label, "malformed_csv", e.message) ]
        end

        def issue(path, code, message)
          ValidationIssue.new(path:, code:, message:)
        end
      end
    end
  end
end
