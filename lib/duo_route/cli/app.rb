# frozen_string_literal: true

module DuoRoute
  module CLI
    class App
      ROOT = File.expand_path("../../..", __dir__)
      DEFAULT_PROVIDERS = File.join(ROOT, "data/examples/providers.json")
      DEFAULT_OPERATIONS = File.join(ROOT, "data/examples/operations_queue_10.json")
      DEFAULT_CONFIG = File.join(ROOT, "config/routing/default.yml")

      def initialize(argv, out: $stdout, err: $stderr, root: ROOT)
        @argv = argv.dup
        @out = out
        @err = err
        @root = root
      end

      def run
        command = @argv.shift
        return help(0) if command.nil? || %w[help --help -h].include?(command)
        case command
        when "strategies" then strategies
        when "validate" then validate
        when "route" then route
        when "demo" then demo
        when "final" then final
        when "generate" then generate
        when "compare" then compare
        when "explain" then explain
        else
          @err.puts "Неизвестная команда: #{command}"
          help(2, io: @err)
        end
      rescue InputError => e
        @err.puts JSON.pretty_generate("status" => "invalid", "errors" => e.issues.map(&:to_h))
        2
      rescue OptionParser::ParseError, Error, KeyError, Errno::ENOENT => e
        @err.puts "Ошибка: #{e.message}"
        2
      end

      private

      def help(code, io: @out)
        io.puts <<~HELP
          DuoRoute #{VERSION} — объяснимый online-роутинг выплат

          Использование: bin/router COMMAND [OPTIONS]

          Команды:
            strategies list / show NAME — каталог семи стратегий
            validate  проверить providers, operations, history и config
            route     выполнить роутинг и записать decisions/report
            demo      создать routing_decisions.json и routing_report.json на public queue
            final     строго создать в корне routing_*_test.json только из operations_queue_test.json
            generate  сгенерировать воспроизводимый набор данных
            compare   сравнить presets на одном исходном snapshot
            explain   показать audit trail одной операции

          Примеры:
            bin/router demo --seed 42
            bin/router route --providers data/examples/providers.json --operations data/examples/operations_queue_10.json --config config/routing/default.yml --preset balanced
            bin/router final --operations operations_queue_test.json --providers data/providers.json --config config/routing/final.yml --seed 42
            bin/router generate --scenario stress --operations 10000 --providers 20 --seed 42 --output tmp/generated

          Запустите bin/router COMMAND --help для параметров команды.
        HELP
        code
      end

      def strategies
        action = @argv.shift
        entries = StrategyCatalog.all
        case action
        when "list"
          raise Error, "лишние аргументы" unless @argv.empty?
          @out.puts DuoRoute.pretty_json(entries)
        when "show"
          name = @argv.shift
          raise Error, "неизвестная стратегия или лишние аргументы" unless entries.key?(name) && @argv.empty?
          @out.puts DuoRoute.pretty_json(entries.fetch(name))
        else raise Error, "используйте strategies list или strategies show NAME"
        end
        0
      end

      def parse_options!(parser)
        parser.parse!(@argv)
        raise Error, "неизвестные аргументы: #{@argv.join(' ')}" unless @argv.empty?
      end

      def common_options(defaults = {})
        options = { providers: DEFAULT_PROVIDERS, operations: DEFAULT_OPERATIONS, config: DEFAULT_CONFIG,
          settings: [], history: nil, outcomes: nil, preset: "balanced", seed: nil, quiet: false }.merge(defaults)
        parser = OptionParser.new do |opts|
          opts.on("--providers PATH", "providers.json") { |value| options[:providers] = value }
          opts.on("--operations PATH", "operations queue JSON") { |value| options[:operations] = value }
          opts.on("--history PATH", "optional history CSV") { |value| options[:history] = value }
          opts.on("--config PATH", "routing YAML/JSON") { |value| options[:config] = value }
          opts.on("--outcomes PATH", "deterministic scripted outcomes JSON") { |value| options[:outcomes] = value }
          opts.on("--preset NAME", "preset (default: balanced)") { |value| options[:preset] = value; options[:strategy_selected] = true }
          opts.on("--strategy NAME", "стратегия или balanced/custom") { |value| options[:preset] = value; options[:strategy_selected] = true }
          opts.on("--simulation-source SOURCE", "history|provider_snapshot|custom|scripted") { |value| options[:settings] << "simulation.source=#{value}" }
          opts.on("--timeout-mode MODE") { |value| options[:settings] << "routing.timeout_mode=#{value}" }
          opts.on("--set PATH=VALUE", "повторяемое изменение YAML/JSON параметра") { |value| options[:settings] << value }
          opts.on("--seed N", Integer, "simulation seed") { |value| options[:seed] = value }
          opts.on("--quiet", "suppress progress summary") { options[:quiet] = true }
          opts.on("-h", "--help") { @out.puts opts; throw :help }
        end
        [ options, parser ]
      end

      def validate
        options, parser = common_options
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        runner = build_runner(options)
        runner.validate!
        @out.puts JSON.pretty_generate("status" => "valid", "providers" => runner.providers_data["providers"].length,
          "operations" => runner.operations.length, "history_rows" => runner.history.length, "preset" => options[:preset])
        0
      end

      def route
        options, parser = common_options(decisions: "routing_decisions.json", report: "routing_report.json")
        parser.on("--decisions PATH", "decisions output") { |value| options[:decisions] = value }
        parser.on("--report PATH", "report output") { |value| options[:report] = value }
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        ensure_distinct_paths!(options)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = build_runner(options, progress: progress_callback(options)).call
        validate_outputs!(result, operation_ids: build_operations(options).map { |item| item["operation_id"] })
        write_result(options, result)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        @out.puts "Готово: #{options[:decisions]}, #{options[:report]} (#{format('%.3f', elapsed)} с)" unless options[:quiet]
        0
      end

      def demo
        options, parser = common_options(history: File.join(ROOT, "data/examples/operations_history.csv"),
          outcomes: File.join(ROOT, "data/examples/demo_outcomes.json"),
          decisions: File.join(@root, "routing_decisions.json"), report: File.join(@root, "routing_report.json"))
        parser.on("--decisions PATH") { |value| options[:decisions] = value }
        parser.on("--report PATH") { |value| options[:report] = value }
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        execute_route_options(options)
      end

      def final
        options, parser = common_options(providers: File.join(@root, "data/providers.json"),
          operations: File.join(@root, "operations_queue_test.json"), config: File.join(@root, "config/routing/final.yml"), quiet: false)
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        unless File.basename(options[:operations]) == "operations_queue_test.json"
          raise Error, "final принимает только файл с точным именем operations_queue_test.json"
        end
        options[:decisions] = File.join(@root, "routing_decisions_test.json")
        options[:report] = File.join(@root, "routing_report_test.json")
        execute_route_options(options)
      end

      def execute_route_options(options)
        ensure_distinct_paths!(options)
        result = build_runner(options, progress: progress_callback(options)).call
        operation_ids = build_operations(options).map { |item| item["operation_id"] }
        validate_outputs!(result, operation_ids:)
        write_result(options, result)
        @out.puts "Готово: #{options[:decisions]}, #{options[:report]}" unless options[:quiet]
        0
      end

      def generate
        options = { scenario: "normal", operations: 100, providers: 4, seed: 42, output: "tmp/generated" }
        parser = OptionParser.new do |opts|
          opts.on("--scenario NAME", Generators::Scenario::NAMES.join(", ")) { |value| options[:scenario] = value }
          opts.on("--operations N", Integer) { |value| options[:operations] = value }
          opts.on("--providers N", Integer) { |value| options[:providers] = value }
          opts.on("--seed N", Integer) { |value| options[:seed] = value }
          opts.on("--output DIR") { |value| options[:output] = value }
          opts.on("-h", "--help") { @out.puts opts; throw :help }
        end
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        raise Error, "operations и providers должны быть положительными" unless options[:operations].positive? && options[:providers].positive?
        bundle = Generators::Scenario.new(name: options[:scenario], operations: options[:operations], providers: options[:providers], seed: options[:seed]).call
        FileUtils.mkdir_p(options[:output])
        atomic_write(File.join(options[:output], "providers.json"), DuoRoute.pretty_json(bundle["providers"]))
        atomic_write(File.join(options[:output], "operations.json"), DuoRoute.pretty_json(bundle["operations"]))
        atomic_write(File.join(options[:output], "outcomes.json"), DuoRoute.pretty_json(bundle["outcomes"]))
        history = CSV.generate { |csv| csv << %w[operation_id created_at amount bank card_brand payment_system status latency_sec]; bundle["history"].each { |row| csv << row } }
        atomic_write(File.join(options[:output], "history.csv"), history)
        atomic_write(File.join(options[:output], "manifest.json"), DuoRoute.pretty_json(bundle["manifest"]))
        @out.puts "Создан набор #{options[:scenario]}: #{options[:output]}"
        0
      end

      def compare
        options, parser = common_options(presets: StrategyCatalog.all.keys.join(","))
        parser.on("--presets LIST") { |value| options[:presets] = value }
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        options[:presets] = options[:preset] if options[:strategy_selected]
        table = options[:presets].split(",").map do |preset|
          result = build_runner(options.merge(preset: preset.strip)).call
          { "preset" => preset.strip, "resolved_configuration" => result.manifest["resolved_configuration"], "manifest" => result.manifest, "approval_rate_pct" => result.report["approval_rate_pct"],
            "fallback_rate_pct" => result.report["fallback_rate_pct"], "average_latency_sec" => result.report["average_latency_sec"],
            "count_absolute_deviation_pp" => result.report["distribution"].values.sum { |row| row["deviation_pp"].abs }.round(2),
            "volume_absolute_deviation_pp" => result.report["volume_distribution"].values.sum { |row| row["deviation_pp"].to_f.abs }.round(2) }
        end
        @out.puts JSON.pretty_generate("counterfactual" => true, "results" => table)
        0
      end

      def explain
        options = { decisions: "routing_decisions.json", operation: nil }
        parser = OptionParser.new do |opts|
          opts.on("--decisions PATH") { |value| options[:decisions] = value }
          opts.on("--operation ID") { |value| options[:operation] = value }
          opts.on("-h", "--help") { @out.puts opts; throw :help }
        end
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        raise Error, "обязателен --operation" unless options[:operation]
        decision = Input::Loader.json_file(options[:decisions]).find { |item| item["operation_id"] == options[:operation] }
        raise Error, "operation #{options[:operation]} не найдена" unless decision
        @out.puts DuoRoute.pretty_json(decision)
        0
      end

      def build_runner(options, progress: nil)
        source = options[:settings].reverse.find { |setting| setting.start_with?("simulation.source=") }&.split("=", 2)&.last
        use_outcomes = options[:outcomes] && (source.nil? || source == "scripted")
        Runner.new(providers_data: Input::Loader.json_file(options[:providers]), operations: build_operations(options),
          history: options[:history] ? Input::Loader.csv_file(options[:history]) : [], config: Input::Loader.config_file(options[:config]),
          outcomes: use_outcomes ? Input::Loader.json_file(options[:outcomes]) : nil,
          preset: options[:preset], seed: options[:seed], settings: options[:settings], progress:)
      end

      def build_operations(options) = Input::Loader.json_file(options[:operations])

      def validate_outputs!(result, operation_ids:)
        validator = Reporting::OutputValidator.new
        issues = validator.decisions(result.decisions, operation_ids:) + validator.report(result.report, expected_total: operation_ids.length)
        raise InputError, issues if issues.any?
      end

      def progress_callback(options)
        return nil if options[:quiet]
        lambda do |done, total, operation|
          @err.puts "Обработано #{done}/#{total}#{operation ? ": #{operation}" : ''}" if total >= 1000 && (done % 1000).zero?
        end
      end

      def ensure_distinct_paths!(options)
        inputs = %i[providers operations config history outcomes].filter_map { |key| options[key] && File.expand_path(options[key]) }
        outputs = [ options.fetch(:decisions), options.fetch(:report), "#{options[:report]}.config.json", "#{options[:report]}.manifest.json" ].map { |path| File.expand_path(path) }
        raise Error, "пути decisions и report должны различаться" if outputs.uniq.length != outputs.length
        raise Error, "выход не может перезаписывать вход" if (inputs & outputs).any?
      end

      def atomic_write(path, content)
        FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
        temp = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
        File.write(temp, content, mode: "wb")
        File.rename(temp, path)
      ensure
        File.unlink(temp) if temp && File.exist?(temp)
      end

      def write_result(options, result)
        atomic_artifacts([
          [ options[:decisions], DuoRoute.pretty_json(result.decisions) ],
          [ options[:report], DuoRoute.pretty_json(result.report) ],
          [ "#{options[:report]}.config.json", DuoRoute.pretty_json(result.manifest["resolved_configuration"]) ],
          [ "#{options[:report]}.manifest.json", DuoRoute.pretty_json(result.manifest) ]
        ])
      end

      def atomic_artifacts(artifacts)
        temps = []
        committed = []
        backups = []
        artifacts.each do |path, content|
          FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
          temp = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
          File.write(temp, content, mode: "wb")
          temps << [ path, temp ]
        end
        backups = temps.filter_map do |path, _|
          next unless File.exist?(path)

          backup = "#{path}.backup-#{Process.pid}-#{SecureRandom.hex(4)}"
          FileUtils.cp(path, backup)
          [ path, backup ]
        end
        temps.each do |path, temp|
          File.rename(temp, path)
          committed << path
        end
      rescue StandardError
        Array(committed).each do |path|
          backup = backups&.find { |original, _| original == path }&.last
          backup ? FileUtils.mv(backup, path, force: true) : FileUtils.rm_f(path)
        end
        raise
      ensure
        Array(temps).each { |_, temp| File.unlink(temp) if File.exist?(temp) }
        Array(backups).each { |_, backup| File.unlink(backup) if File.exist?(backup) }
      end
    end
  end
end
