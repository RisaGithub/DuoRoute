# frozen_string_literal: true

module DuoRoute
  module Input
    class Loader
      MAX_BYTES = 128 * 1024 * 1024

      class << self
        def json_file(path, max_bytes: MAX_BYTES)
          parse_json(read(path, max_bytes:), path)
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

        def read(path, max_bytes: MAX_BYTES)
          raise InputError, [ issue(path, "file_not_found", "файл не найден") ] unless File.file?(path)
          raise InputError, [ issue(path, "file_too_large", "файл больше #{MAX_BYTES} байт") ] if File.size(path) > max_bytes

          content = File.read(path, max_bytes + 1, encoding: "UTF-8")
          ensure_size!(content, path, max_bytes:)
          content
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          raise InputError, [ issue(path, "invalid_encoding", "ожидается UTF-8") ]
        end

        def ensure_size!(content, label, max_bytes: MAX_BYTES)
          raise InputError, [ issue(label, "invalid_encoding", "ожидается UTF-8") ] unless content.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          raise InputError, [ issue(label, "empty_file", "файл пуст") ] if content.strip.empty?
          raise InputError, [ issue(label, "file_too_large", "данные больше #{MAX_BYTES} байт") ] if content.bytesize > max_bytes
        end

        def parse_json(content, label)
          json_numbers(JSON.parse(content, decimal_class: BigDecimal), label)
        rescue JSON::ParserError => e
          raise InputError, [ issue(label, "malformed_json", "некорректный JSON") ]
        end

        def json_numbers(value, path)
          case value
          when BigDecimal
            begin
              Money.number(value)
            rescue Error
              raise InputError, [ issue(path, "unsupported_precision", "число нельзя точно представить текущим JSON-интерфейсом") ]
            end
          when Hash then value.transform_keys(&:to_s).to_h { |key, item| [ key, json_numbers(item, "#{path}.#{key}") ] }
          when Array then value.map.with_index { |item, index| json_numbers(item, "#{path}[#{index}]") }
          else value
          end
        end

        def parse_yaml(content, label)
          value = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
          value
        rescue Psych::Exception => e
          raise InputError, [ issue(label, "malformed_yaml", e.message) ]
        end

        def parse_csv(content, label)
          rows = CSV.parse(content)
          headers = rows.shift
          unless headers && headers.all? { |name| name.is_a?(String) && !name.strip.empty? } && headers.uniq == headers
            raise InputError, [ issue(label, "invalid_csv_headers", "заголовки должны быть непустыми и уникальными") ]
          end
          required = %w[operation_id created_at amount bank payment_system status latency_sec]
          missing = required - headers
          raise InputError, [ issue(label, "missing_csv_headers", "отсутствуют столбцы: #{missing.join(', ')}") ] if missing.any?
          rows.map.with_index(2) do |row, line|
            unless row.length == headers.length
              raise InputError, [ issue("#{label}[#{line}]", "csv_column_count", "ожидалось #{headers.length} столбцов, получено #{row.length}") ]
            end
            headers.zip(row).to_h.merge("_line" => line)
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
