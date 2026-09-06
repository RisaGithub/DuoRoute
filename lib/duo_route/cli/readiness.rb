# frozen_string_literal: true

require "rbconfig"
require "stringio"

module DuoRoute
  module CLI
    module Readiness
      FINAL_FILES = %w[operations_queue_test.json routing_decisions_test.json routing_report_test.json].freeze

      private

      def rehearse_final
        options, parser = common_options(providers: File.join(App::ROOT, "data/providers.json"),
          operations: File.join(App::ROOT, "data/operations_queue_10.json"), config: File.join(App::ROOT, "config/routing/final.yml"))
        allow_reference_mismatch = false
        parser.on("--allow-reference-mismatch", "разрешить только подтверждённое расхождение статического эталона") { allow_reference_mismatch = true }
        mismatch = false
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        Dir.mktmpdir("duoroute-rehearsal-") do |dir|
          queue = File.join(dir, "operations_queue_test.json")
          FileUtils.cp(options[:operations], queue)
          args = [ "final", "--operations", queue, "--providers", File.expand_path(options[:providers]), "--config", File.expand_path(options[:config]), "--preset", options[:preset], "--quiet" ]
          args << "--allow-reference-mismatch" if allow_reference_mismatch
          %i[history outcomes seed].each { |key| args.concat([ "--#{key}", options[key].to_s ]) if options[key] }
          args.concat([ "--audit-level", options[:audit_level] ]) if options[:audit_level]
          options[:settings].each { |value| args.concat([ "--set", value ]) }
          previous = nil
          2.times do
            final_output = StringIO.new
            code = self.class.new(args, root: dir, out: final_output, err: @err).run
            @out.puts final_output.string
            raise Error, "final pipeline failed in rehearsal" unless code.zero?
            decisions = File.join(dir, "routing_decisions_test.json")
            report = File.join(dir, "routing_report_test.json")
            run_check!("independent audit", RbConfig.ruby, File.join(App::ROOT, "script/audit_submission.rb"),
              "--providers", options[:providers], "--operations", queue, "--decisions", decisions, "--report", report,
              "--config", File.join(dir, "tmp/final_audit/config.json"))
            current = [ File.read(decisions), deterministic_report(JSON.parse(File.read(report))) ]
            raise Error, "rehearsal is not deterministic" if previous && previous != current
            previous = current
            mismatch = public_validator!(options, decisions, strict: !allow_reference_mismatch) == :reference_mismatch || mismatch
          end
        end
        @out.puts "#{mismatch ? 'PASS WITH REFERENCE MISMATCH' : 'REHEARSAL PASS'}: настоящий final, обязательный semantic audit и повторяемость проверены; временные файлы удалены."
        0
      end

      def deterministic_report(report)
        report.fetch("reproducibility").delete("duration_ms")
        report
      end

      def public_validator!(options, decisions, strict: true, announce: true)
        matches = %i[providers operations].all? do |key|
          filename = key == :providers ? "providers.json" : "operations_queue_10.json"
          Input::Loader.json_file(options[key]) == Input::Loader.json_file(File.join(App::ROOT, "data", filename))
        end
        unless matches
          @out.puts "Public validator: N/A (валидатор организаторов рассчитан только на public queue/snapshot)."
          return
        end
        output, status = Open3.capture2e(RbConfig.ruby, File.join(App::ROOT, "script/validate_10.rb"), decisions)
        if status.success?
          @out.puts "PASS: public validator" if announce
          return :passed
        end
        @out.puts output
        unless reference_only_failure?(output, status, decisions)
          raise Error, "public validator failed: ошибка не является подтверждённым reference mismatch"
        end
        explanation = "REFERENCE MISMATCH: статический эталон ожидает первоначального кандидата; selected_provider содержит итог после rejected/expired. Semantic audit обязателен."
        @out.puts explanation
        raise Error, "#{explanation} Для явного разрешения используйте --allow-reference-mismatch" if strict
        :reference_mismatch
      end

      def reference_only_failure?(output, status, decisions)
        return false unless status.exitstatus == 1
        rows = Input::Loader.json_file(decisions)
        reference = Input::Loader.json_file(File.join(App::ROOT, "data/reference_decisions.json"))
        expected = reference.fetch("deterministic_cases").filter_map do |item|
          row = rows.find { |decision| decision["operation_id"] == item["operation_id"] }
          next unless row && row["selected_provider"] != item["required_provider"]
          calls = row.fetch("attempts").select { |attempt| attempt.key?("result") }
          first = calls.first
          next unless first && first["provider"] == item["required_provider"] && %w[rejected expired].include?(first["result"])
          "❌ #{row['operation_id']}: выбран #{row['selected_provider']}, ожидался #{item['required_provider']}"
        end
        failures = output.lines.map(&:strip).grep(/^❌ /).reject { |line| line.start_with?("❌ Ошибок:") }
        count = output[/❌ Ошибок:\s+(\d+)/, 1]
        expected.any? && failures.sort == expected.sort && count.to_i == expected.length
      end

      def run_check!(label, *command, announce: true)
        output, status = Open3.capture2e(*command, chdir: App::ROOT)
        raise Error, "#{label}: failed (exit #{status.exitstatus})\n#{output}" unless status.success?
        @out.puts "PASS: #{label}" if announce
        output
      end

      def readiness
        full = false
        parser = OptionParser.new do |opts|
          opts.on("--full", "дополнительно локальные tests/style/security/zeitwerk") { full = true }
          opts.on("-h", "--help") { @out.puts opts; throw :help, :help }
        end
        return 0 if catch(:help) { parse_options!(parser); nil } == :help
        problems = []
        check = lambda do |label, &block|
          block.call
          @out.puts "PASS: #{label}"
        rescue StandardError => e
          problems << "#{label}: #{e.is_a?(Error) ? e.message : e.class.name}"
        end
        check.call("Ruby") { raise Error, "нужна Ruby 3.4.10, получена #{RUBY_VERSION}" unless RUBY_VERSION == "3.4.10" }
        check.call("required files") do
          %w[README.md docs/CLI.md docs/WEB.md docs/ALGORITHM.md docs/ARCHITECTURE.md docs/CRITERIA_COMPLIANCE.md config/routing/default.yml config/routing/final.yml data/providers.json data/operations_queue_10.json data/operations_history.csv script/audit_submission.rb script/validate_10.rb].each do |path|
            raise Error, "missing #{path}" unless File.file?(File.join(@root, path))
          end
        end
        check.call("config, seven strategies, providers, history") do
          raise Error, "seven strategies required" unless StrategyCatalog.all.size == 7
          options, = common_options
          options[:providers] = File.join(@root, "data/providers.json")
          options[:operations] = File.join(@root, "data/operations_queue_10.json")
          options[:config] = File.join(@root, "config/routing/default.yml")
          options[:history] = File.join(@root, "data/operations_history.csv")
          build_runner(options).validate!
        end
        check.call("default strategy evidence and configuration") do
          selection = DefaultSelection.record
          %w[default final].each do |name|
            settings = Input::Loader.config_file(File.join(App::ROOT, "config/routing/#{name}.yml"))
            raise Error, "default strategy differs from selection" unless settings.dig("routing", "default_strategy") == selection.fetch("strategy")
            resolved = Configuration.resolve(settings, strategy: selection.fetch("strategy"))
            raise Error, "default weights differ from evidence" unless resolved.dig("presets", selection["strategy"], "weights") == selection["weights"]
          end
          raise Error, "default study incomplete" if selection["version"] == "study-pending"
        end
        check.call("public demo, determinism, validators") do
          Dir.mktmpdir("duoroute-readiness-") do |dir|
            args = [ "demo", "--seed", "42", "--quiet" ]
            before = nil
            2.times do
              raise Error, "demo failed" unless self.class.new(args, root: dir, out: StringIO.new, err: StringIO.new).run.zero?
              decisions = File.join(dir, "routing_decisions.json")
              report = File.join(dir, "routing_report.json")
              current = [ File.read(decisions), deterministic_report(JSON.parse(File.read(report))) ]
              raise Error, "nondeterministic demo" if before && before != current
              before = current
              run_check!("independent audit", RbConfig.ruby, File.join(App::ROOT, "script/audit_submission.rb"),
                "--providers", App::DEFAULT_PROVIDERS, "--operations", App::DEFAULT_OPERATIONS, "--decisions", decisions, "--report", report,
                "--config", "#{report}.config.json", announce: false)
              public_validator!({ providers: App::DEFAULT_PROVIDERS, operations: App::DEFAULT_OPERATIONS }, decisions, announce: false)
              { "providers" => App::DEFAULT_PROVIDERS, "operations" => App::DEFAULT_OPERATIONS,
                "routing_config" => "#{report}.config.json", "routing_decisions" => decisions, "routing_report" => report,
                "outcomes" => File.join(App::ROOT, "data/examples/demo_outcomes.json") }.each do |name, path|
                run_check!("schema #{name}", RbConfig.ruby, File.join(App::ROOT, "script/check_schemas.rb"), File.join(App::ROOT, "schemas/#{name}.schema.json"), path, announce: false)
              end
            end
          end
        end
        check.call("production documentation") { run_check!("production documentation", RbConfig.ruby, File.join(App::ROOT, "script/check_production_docs.rb"), announce: false) }
        check.call("Markdown links") { run_check!("Markdown links", RbConfig.ruby, File.join(App::ROOT, "script/check_markdown_links.rb"), announce: false) }
        check.call("no premature final files") do
          present = FINAL_FILES.select { |file| File.exist?(File.join(@root, file)) }
          raise Error, "pre-final mode: present #{present.join(', ')}" if present.any?
        end
        check.call("no tracked internal files") do
          tracked, status = Open3.capture2e("git", "ls-files", "-z", "--", "AGENTS.md", "artifacts/verification", "docs/screenshots", chdir: @root)
          raise Error, "cannot list Git files" unless status.success?
          raise Error, "internal files are tracked: #{tracked.split("\0").join(', ')}" unless tracked.empty?
        end
        check.call("Git") do
          status, exit_status = Open3.capture2e("git", "status", "--porcelain=v1", "-z", chdir: @root)
          raise Error, "cannot read Git status" unless exit_status.success?
          raise Error, "unresolved merge conflicts" if status.split("\0").any? { |row| %w[DD AU UD UA DU AA UU].include?(row[0, 2]) }
          @out.puts "Git: #{status.split("\0").length} status entries (contents withheld; dirty tree is allowed)."
        end
        if full
          [ [ "tests", RbConfig.ruby, "bin/rails", "test" ], [ "RuboCop", { "RUBOCOP_CACHE_ROOT" => File.join(Dir.tmpdir, "duoroute-rubocop-cache") }, RbConfig.ruby, "bin/rubocop" ],
            [ "Brakeman", "bundle", "exec", "brakeman", "-q", "--no-pager" ],
            [ "dependency audit (offline; cached advisory DB required)", "bundle", "exec", "ruby", "-rbundler/audit/database", "-rbundler/audit/cli", "-e", 'abort "local advisory DB missing" unless Bundler::Audit::Database.exists?; Bundler::Audit::CLI.start(["check", "--no-update", "--config", "config/bundler-audit.yml"])' ],
            [ "Zeitwerk", RbConfig.ruby, "bin/rails", "zeitwerk:check" ] ].each do |label, *command|
            check.call(label) { run_check!(label, *command, announce: false) }
          end
        end
        problems.each { |problem| @out.puts "FAIL: #{problem}" }
        @out.puts(problems.empty? ? "READY" : "NOT READY")
        problems.empty? ? 0 : 2
      end

      def feasibility
        path = "routing_report.json"
        parser = OptionParser.new { |opts| opts.on("--report PATH") { |value| path = value } }
        parse_options!(parser)
        @out.puts DuoRoute.pretty_json(Input::Loader.json_file(path).fetch("goal_feasibility"))
        0
      end
    end
  end
end

DuoRoute::CLI::App.include(DuoRoute::CLI::Readiness)
