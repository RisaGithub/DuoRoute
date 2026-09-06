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
        when "evaluate-default" then evaluate_default
        when "strategies" then strategies
        when "validate" then validate
        when "route" then route
        when "demo" then demo
        when "final" then final
        when "rehearse-final" then rehearse_final
        when "readiness" then readiness
        when "feasibility" then feasibility
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
      rescue OptionParser::ParseError, Error, KeyError, SystemCallError, IOError => e
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
            rehearse-final  репетиция настоящего final во временном каталоге
            readiness  локальная проверка готовности (--full для расширенной)
            feasibility --report PATH  наблюдаемая достижимость целей
            evaluate-default  сравнить кандидаты на фиксированных сценариях и seed
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
          settings: [], history: File.file?(File.join(ROOT, "data/operations_history.csv")) ? File.join(ROOT, "data/operations_history.csv") : nil, outcomes: nil, preset: "balanced", seed: nil, quiet: false }.merge(defaults)
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
          opts.on("--audit-level LEVEL", %w[full submission compact], "full|submission|compact") { |value| options[:audit_level] = value }
          opts.on("--quiet", "suppress progress summary") { options[:quiet] = true }
          opts.on("-h", "--help") { @out.puts opts; throw :help, :help }
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
        execute_route_options(options)
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
          operations: File.join(@root, "operations_queue_test.json"), config: File.join(@root, "config/routing/final.yml"), quiet: false, final: true, history: nil, audit_level: "submission")
        parser.on("--dry-run", "расчёт и проверки без записи финальных файлов") { options[:dry_run] = true }
        parser.on("--explain-summary", "источники симуляции, конфликты и рекомендации") { options[:explain_summary] = true }
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        unless File.basename(options[:operations]) == "operations_queue_test.json"
          raise Error, "final принимает только файл с точным именем operations_queue_test.json"
        end
        options[:decisions] = File.join(@root, "routing_decisions_test.json")
        options[:report] = File.join(@root, "routing_report_test.json")
        options[:audit_dir] = File.join(@root, "tmp/final_audit")
        default_history = File.join(@root, "data/operations_history.csv")
        options[:history] ||= default_history if File.file?(default_history)
        execute_route_options(options)
      end

      def execute_route_options(options)
        ensure_distinct_paths!(options)
        runner = build_runner(options, progress: progress_callback(options))
        runner.validate!
        if options[:final]
          if runner.config.dig("simulation", "source") == "history" && runner.history.empty?
            raise Error, "final: источник history требует непустой data/operations_history.csv или --history PATH"
          end
          @out.puts "Входы: #{options.slice(:operations, :providers, :history, :config, :outcomes)}"
          @out.puts "Стратегия: #{options[:preset]}; seed: #{runner.config['seed']}; simulation: #{runner.config.dig('simulation', 'source')}"
          check_space!(@root, 1024 * 1024)
        end
        result = runner.call
        operation_ids = runner.operations.map { |item| item["operation_id"] }
        validate_outputs!(result, operation_ids:)
        if options[:explain_summary]
          @out.puts DuoRoute.pretty_json(result.report.slice("simulation", "target_exceptions", "recommendations", "goal_feasibility"))
        end
        if options[:dry_run]
          # Exercise serialization and disk validation in a disposable directory too.
          Dir.mktmpdir("duoroute-dry-run-") do |dir|
            write_result(options.merge(decisions: "#{dir}/decisions.json", report: "#{dir}/report.json", audit_dir: dir), result)
          end
          @out.puts "Dry-run успешен: #{operation_ids.length} операций; финальные файлы не записаны"
          return 0
        end
        write_result(options, result)
        @out.puts "Итог: #{operation_ids.length} операций; approval #{result.report['approval_rate_pct']}%; fallback #{result.report['fallback_rate_pct']}%; latency #{result.report['average_latency_sec']} с" unless options[:quiet]
        result.report.fetch("goal_feasibility", {}).each { |name, row| @out.puts "Цель #{name}: #{row['explanation']}" } unless options[:quiet]
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
          opts.on("-h", "--help") { @out.puts opts; throw :help, :help }
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
          opts.on("-h", "--help") { @out.puts opts; throw :help, :help }
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
          preset: options[:preset], seed: options[:seed], settings: options[:settings], progress:, audit_level: options[:audit_level] || "full")
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
        inputs = %i[providers operations config history outcomes].filter_map { |key| options[key] && canonical_path(options[key]) }
        outputs = [ options.fetch(:decisions), options.fetch(:report), *audit_paths(options) ].map { |path| canonical_path(path) }
        raise Error, "пути decisions и report должны различаться" if outputs.uniq.length != outputs.length
        collision = inputs.product(outputs).any? { |input, output| File.exist?(input) && File.exist?(output) && File.identical?(input, output) }
        raise Error, "выход не может перезаписывать вход" if (inputs & outputs).any? || collision
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
        config_path, manifest_path = audit_paths(options)
        artifacts = [
          [ options[:decisions], DuoRoute.pretty_json(result.decisions) ],
          [ options[:report], DuoRoute.pretty_json(result.report) ],
          [ config_path, DuoRoute.pretty_json(result.manifest["resolved_configuration"]) ],
          [ manifest_path, DuoRoute.pretty_json(result.manifest) ]
        ]
        check_space!(@root, artifacts.sum { |_, content| content.bytesize } * 3) if options[:final]
        lock_dir = options[:audit_dir] || File.join(@root, "tmp/routing_audit")
        FileUtils.mkdir_p(lock_dir)
        File.open(File.join(lock_dir, ".write.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          raise Error, "другой процесс уже записывает результаты" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          atomic_artifacts(artifacts) do |temps|
            staged = RunResult.new(decisions: Input::Loader.json_file(temps[0][1], max_bytes: artifacts[0][1].bytesize), report: Input::Loader.json_file(temps[1][1], max_bytes: artifacts[1][1].bytesize), manifest: result.manifest)
            validate_outputs!(staged, operation_ids: result.decisions.map { |row| row["operation_id"] })
            if options[:final]
              run_check!("independent final audit", RbConfig.ruby, File.join(ROOT, "script/audit_submission.rb"),
                "--providers", options[:providers], "--operations", options[:operations],
                "--decisions", temps[0][1], "--report", temps[1][1], "--config", temps[2][1])
            end
          end
        end
      end

      def audit_paths(options)
        if options[:audit_dir]
          [ File.join(options[:audit_dir], "config.json"), File.join(options[:audit_dir], "manifest.json") ]
        else
          [ "#{options[:report]}.config.json", "#{options[:report]}.manifest.json" ]
        end
      end

      def canonical_path(path)
        expanded = File.expand_path(path)
        return File.realpath(expanded) if File.exist?(expanded)
        parent = File.dirname(expanded)
        parent == expanded ? expanded : File.join(canonical_path(parent), File.basename(expanded))
      end

      def check_space!(directory, required)
        output, status = Open3.capture2("df", "-Pk", directory)
        available = output.lines.last.to_s.split[-3]
        raise Error, "не удалось проверить свободное место" unless status.success? && available&.match?(/\A\d+\z/)
        raise Error, "недостаточно места: нужно #{required} байт" if available.to_i * 1024 < required
        raise Error, "каталог недоступен для записи: #{directory}" unless File.writable?(directory)
      end

      def evaluate_default
        raise Error, "evaluate-default не принимает параметры" unless @argv.empty?
        report = Evaluation::DefaultStrategy.new.call
        report["robustness"] = Evaluation::Robustness.new.call
        path = File.join(@root, "artifacts/verification/default_strategy_evaluation.json")
        atomic_write(path, DuoRoute.pretty_json(report))
        @out.puts "Оценка: #{path}; выбран #{report['selected_candidate']}"
        0
      end

      def rename_artifact(source, target) = File.rename(source, target)

      def atomic_artifacts(artifacts)
        temps = []
        committed = []
        backups = []
        artifacts.each do |path, content|
          FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
          temp = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
          temps << [ path, temp ]
          File.open(temp, "wb", 0o600) { |file| file.write(content); file.flush; file.fsync }
        end
        yield temps if block_given?
        temps.each do |path, _|
          next unless File.exist?(path)

          backup = "#{path}.backup-#{Process.pid}-#{SecureRandom.hex(4)}"
          backups << [ path, backup ]
          FileUtils.cp(path, backup)
        end
        temps.each do |path, temp|
          rename_artifact(temp, path)
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
