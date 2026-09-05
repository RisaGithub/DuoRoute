# frozen_string_literal: true

module DuoRoute
  module Validation
    class InputValidator
      PROVIDER_REQUIRED = %w[payment_system status traffic_percentage daily_approved_amount in_progress_count
        in_progress_amount available_requisites conversion_24h banks exclude_banks provider_margin_pct
        merchant_margin_pct allow_negative_agreement].freeze
      NUMERIC_FIELDS = %w[traffic_percentage limit_amount_min limit_amount_max daily_amount_limit daily_approved_amount
        in_progress_count_limit in_progress_count in_progress_amount_limit in_progress_amount available_requisites
        conversion_24h avg_latency_sec provider_margin_pct merchant_margin_pct priority requests_per_minute_limit
        volume_share_pct daily_turnover_min daily_turnover_max preferred_amount_min preferred_amount_max].freeze
      POLICY_NAMES = %w[count_share volume_share cascade preferred_amount conversion load_safe intensity turnover_commitment economy latency].freeze
      TIMEOUT_MODES = %w[fallback_on_timeout hold_until_status].freeze

      def call(providers_data:, operations:, config:, history: [])
        @issues = []
        validate_provider_root(providers_data)
        validate_operations(operations)
        validate_config(config)
        validate_history(history)
        validate_cross_references(providers_data, operations, history)
        @issues
      end

      private

      def validate_provider_root(data)
        unless data.is_a?(Hash)
          add("$", "wrong_type", "providers должен быть объектом")
          return
        end
        required(data, %w[snapshot_at gateway merchant providers], "$")
        %w[gateway merchant].each { |field| nonblank(data[field], "$.#{field}") }
        iso_time(data["snapshot_at"], "$.snapshot_at") if data.key?("snapshot_at")
        unless data["providers"].is_a?(Array) && data["providers"].any?
          add("$.providers", "empty_providers", "ожидается непустой массив")
          return
        end

        names = []
        data["providers"].each_with_index do |provider, index|
          path = "$.providers[#{index}]"
          unless provider.is_a?(Hash)
            add(path, "wrong_type", "провайдер должен быть объектом")
            next
          end
          required(provider, PROVIDER_REQUIRED, path)
          %w[payment_system status].each { |field| nonblank(provider[field], "#{path}.#{field}") }
          (PROVIDER_REQUIRED & NUMERIC_FIELDS).each { |field| numeric(provider[field], "#{path}.#{field}") }
          %w[in_progress_count in_progress_count_limit available_requisites requests_per_minute_limit priority].each do |field|
            value = provider[field]
            add("#{path}.#{field}", "integer_required", "ожидается целое число") if !value.nil? && (!value.is_a?(Numeric) || !value.finite? || value != value.to_i)
          end
          add("#{path}.allow_negative_agreement", "wrong_type", "ожидается boolean") unless [ true, false ].include?(provider["allow_negative_agreement"])
          NUMERIC_FIELDS.each { |field| numeric(provider[field], "#{path}.#{field}") if provider.key?(field) && !provider[field].nil? }
          nonnegative_fields(provider, path)
          range(provider["traffic_percentage"], 0, 100, "#{path}.traffic_percentage")
          range(provider["volume_share_pct"], 0, 100, "#{path}.volume_share_pct") if provider.key?("volume_share_pct")
          range(provider["conversion_24h"], 0, 1, "#{path}.conversion_24h")
          add("#{path}.banks", "wrong_type", "ожидается массив строк") unless provider["banks"].is_a?(Array) && provider["banks"].all? { |v| v.is_a?(String) }
          add("#{path}.exclude_banks", "wrong_type", "ожидается boolean") unless [ true, false ].include?(provider["exclude_banks"])
          names << provider["payment_system"] if provider["payment_system"].is_a?(String)
        end
        names.tally.each { |name, count| add("$.providers", "duplicate_payment_system", "#{name.inspect} встречается #{count} раза") if count > 1 }
        fallback = data["providers"].find { |p| p.is_a?(Hash) && p["payment_system"] == "spacepayments" }
        add("$.providers", "fallback_missing", "обязателен provider spacepayments") unless fallback
        if fallback && (fallback["status"] != "active" || !fallback["available_requisites"].is_a?(Numeric) || !fallback["available_requisites"].finite? || fallback["available_requisites"] <= 0)
          add("$.providers", "fallback_unavailable", "spacepayments должен быть active и иметь доступные реквизиты")
        end
        external = data["providers"].select { |p| p.is_a?(Hash) && p["payment_system"] != "spacepayments" }
        total = external.sum { |p| p["traffic_percentage"].is_a?(Numeric) && p["traffic_percentage"].finite? ? p["traffic_percentage"] : 0 }
        add("$.providers", "traffic_share_sum", "сумма traffic_percentage внешних провайдеров #{total}, ожидается 100") unless external.empty? || (total - 100).abs < 0.001
      end

      def validate_operations(operations)
        unless operations.is_a?(Array)
          add("$operations", "wrong_type", "очередь должна быть массивом")
          return
        end
        add("$operations", "empty_queue", "очередь не должна быть пустой") if operations.empty?
        ids = []
        operations.each_with_index do |operation, index|
          path = "$operations[#{index}]"
          unless operation.is_a?(Hash)
            add(path, "wrong_type", "операция должна быть объектом")
            next
          end
          required(operation, %w[operation_id created_at amount bank], path)
          nonblank(operation["operation_id"], "#{path}.operation_id")
          ids << operation["operation_id"] if operation["operation_id"].is_a?(String)
          iso_time(operation["created_at"], "#{path}.created_at") if operation.key?("created_at")
          numeric(operation["amount"], "#{path}.amount") if operation.key?("amount")
          add("#{path}.amount", "amount_not_positive", "сумма должна быть больше нуля") if operation["amount"].is_a?(Numeric) && operation["amount"] <= 0
          add("#{path}.bank", "wrong_type", "банк должен быть непустой строкой") unless operation["bank"].is_a?(String) && !operation["bank"].strip.empty?
        end
        ids.tally.each { |id, count| add("$operations", "duplicate_operation_id", "#{id.inspect} встречается #{count} раза") if count > 1 }
      end

      def validate_config(config)
        unless config.is_a?(Hash)
          add("$config", "wrong_type", "конфигурация должна быть объектом")
          return
        end
        timeout = config.fetch("routing", {}).fetch("timeout_mode", "fallback_on_timeout")
        add("$config.routing.timeout_mode", "unknown_timeout_mode", "допустимы #{TIMEOUT_MODES.join(', ')}") unless TIMEOUT_MODES.include?(timeout)
        presets = config["presets"]
        add("$config.presets", "missing_presets", "ожидается непустой объект presets") unless presets.is_a?(Hash) && presets.any?
        Array(presets&.to_a).each do |preset_name, preset|
          weights = preset.is_a?(Hash) ? preset["weights"] : nil
          unless weights.is_a?(Hash) && weights.any?
            add("$config.presets.#{preset_name}.weights", "missing_weights", "ожидается непустой объект")
            next
          end
          weights.each do |name, weight|
            add("$config.presets.#{preset_name}.weights.#{name}", "unknown_policy", "неизвестная policy") unless POLICY_NAMES.include?(name)
            add("$config.presets.#{preset_name}.weights.#{name}", "invalid_weight", "вес должен быть неотрицательным числом") unless weight.is_a?(Numeric) && weight.finite? && weight >= 0
          end
          add("$config.presets.#{preset_name}.weights", "zero_weights", "хотя бы один вес должен быть положительным") if weights.values.all? { |v| !v.is_a?(Numeric) || v <= 0 }
        end
      end

      def validate_history(history)
        unless history.is_a?(Array)
          add("$history", "wrong_type", "история должна быть массивом")
          return
        end
        seen = {}
        history.each_with_index do |row, index|
          unless row.is_a?(Hash)
            add("$history[#{index + 2}]", "wrong_type", "строка истории должна быть объектом")
            next
          end
          path = "$history[#{row['_line'] || index + 2}]"
          required(row, %w[operation_id created_at amount bank payment_system status latency_sec], path)
          %w[operation_id bank payment_system].each { |field| nonblank(row[field], "#{path}.#{field}") }
          signature = row.reject { |key, _| key == "_line" }
          add(path, "duplicate_history_row", "повтор строки #{seen[signature]}") if seen.key?(signature)
          seen[signature] = path
          iso_time(row["created_at"], "#{path}.created_at") if row["created_at"]
          %w[amount latency_sec].each do |field|
            begin
              value = BigDecimal(row[field].to_s)
              raise ArgumentError unless value.finite? && (field == "amount" ? value.positive? : value >= 0)
            rescue ArgumentError, TypeError
              add("#{path}.#{field}", "invalid_number", "ожидается #{field == 'amount' ? 'положительное' : 'неотрицательное'} конечное число")
            end
          end
          add("#{path}.status", "invalid_status", "неизвестный status") unless %w[approved rejected expired].include?(row["status"])
        end
      end

      def required(hash, fields, path)
        fields.each { |field| add("#{path}.#{field}", "required", "обязательное поле отсутствует") unless hash.key?(field) && !hash[field].nil? }
      end

      def numeric(value, path)
        add(path, "wrong_type", "ожидается число") unless value.is_a?(Numeric) && value.finite? && value.to_f.finite?
      end

      def nonnegative_fields(provider, path)
        NUMERIC_FIELDS.each do |field|
          value = provider[field]
          add("#{path}.#{field}", "negative_value", "значение не может быть отрицательным") if value.is_a?(Numeric) && value.negative?
        end
        %w[preferred_amount daily_turnover].each do |prefix|
          low, high = provider.values_at("#{prefix}_min", "#{prefix}_max")
          add(path, "invalid_range", "#{prefix}: минимум больше максимума") if low.is_a?(Numeric) && high.is_a?(Numeric) && low > high
        end
        if provider["limit_amount_min"].is_a?(Numeric) && provider["limit_amount_max"].is_a?(Numeric) && provider["limit_amount_min"] > provider["limit_amount_max"]
          add(path, "invalid_amount_range", "limit_amount_min больше limit_amount_max")
        end
      end

      def range(value, min, max, path)
        return unless value.is_a?(Numeric)
        add(path, "out_of_range", "ожидается значение от #{min} до #{max}") unless value.between?(min, max)
      end

      def iso_time(value, path)
        raise ArgumentError unless value.is_a?(String)
        raise ArgumentError unless value.match?(/T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/)
        parts = Date._iso8601(value)
        raise ArgumentError unless Date.valid_date?(parts[:year], parts[:mon], parts[:mday]) && parts[:hour] < 24 && parts[:min] < 60 && parts[:sec] < 60
        Time.iso8601(value)
      rescue ArgumentError, TypeError
        add(path, "invalid_iso8601", "ожидается ISO-8601 время")
      end

      def nonblank(value, path)
        add(path, "wrong_type", "ожидается непустая строка") unless value.is_a?(String) && !value.strip.empty?
      end

      def validate_cross_references(data, operations, history)
        return unless data.is_a?(Hash) && data["providers"].is_a?(Array)
        names = data["providers"].filter_map { |provider| provider["payment_system"] if provider.is_a?(Hash) }
        if history.is_a?(Array)
          history.each_with_index do |row, index|
            next unless row.is_a?(Hash)
            add("$history[#{row['_line'] || index + 2}].payment_system", "unknown_provider", "провайдер отсутствует в snapshot") unless names.include?(row["payment_system"])
          end
        end
        return unless operations.is_a?(Array)
        snapshot = Time.iso8601(data["snapshot_at"]) rescue nil
        operations.each_with_index do |operation, index|
          next unless snapshot && operation.is_a?(Hash)
          at = Time.iso8601(operation["created_at"]) rescue nil
          add("$operations[#{index}].created_at", "before_snapshot", "операция раньше snapshot_at") if at && at < snapshot
        end
      end

      def add(path, code, message)
        @issues << ValidationIssue.new(path:, code:, message:)
      end
    end
  end
end
