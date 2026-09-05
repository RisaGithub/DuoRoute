# frozen_string_literal: true

module DuoRoute
  RunResult = Data.define(:decisions, :report, :manifest)

  class Engine
    def initialize(providers_data:, operations:, config:, preset:, simulator:, history: [], progress: nil,
      constraint_registry: Constraints::Registry.new, clock: Process)
      @providers_data = providers_data
      @providers = providers_data.fetch("providers")
      @operations = operations.each_with_index.sort_by { |(operation, index)| [ Time.iso8601(operation["created_at"]), index ] }.map(&:first)
      @config = config
      @preset = preset
      @simulator = simulator
      @history = history
      @progress = progress
      @constraints = constraint_registry
      @clock = clock
      preset_config = config.fetch("presets").fetch(preset)
      @scorer = Scorer.new(weights: preset_config.fetch("weights"), policy_priorities: preset_config["policy_priorities"])
      @timeout_mode = config.dig("routing", "timeout_mode") || "fallback_on_timeout"
      @fallback_name = config.dig("routing", "fallback_provider") || "spacepayments"
    end

    def call(manifest: {})
      started = monotonic
      state = State::Store.new(@providers)
      decisions = @operations.map.with_index do |operation, index|
        @progress&.call(index, @operations.length, operation["operation_id"])
        route_operation(operation, state)
      end
      @progress&.call(@operations.length, @operations.length, nil)
      duration_ms = ((monotonic - started) * 1000).round(3)
      final_manifest = manifest.merge("schema_version" => SCHEMA_VERSION, "app_version" => VERSION,
        "ruby_version" => RUBY_VERSION, "duration_ms" => duration_ms, "preset" => @preset,
        "timeout_mode" => @timeout_mode)
      report = Reporting::ReportBuilder.new(providers_data: @providers_data, operations: @operations,
        decisions:, state:, history: @history, manifest: final_manifest).call
      RunResult.new(decisions:, report:, manifest: final_manifest)
    end

    private

    def route_operation(operation, state)
      at = Time.iso8601(operation["created_at"])
      before = state.snapshot(at:)
      external = @providers.reject { |provider| provider["payment_system"] == @fallback_name }
      fallback = @providers.find { |provider| provider["payment_system"] == @fallback_name }
      evaluations = external.to_h do |provider|
        [ provider["payment_system"], @constraints.evaluate(provider:, operation:, state:) ]
      end
      eligible = external.select { |provider| evaluations.dig(provider["payment_system"], "eligible") }
      ranking = @scorer.rank(providers: eligible, operation:, state:)
      attempts = hard_failure_attempts(external, evaluations)
      selected = nil
      selected_outcome = nil
      attempted_names = []

      ranking.each_with_index do |rank, index|
        provider = external.find { |item| item["payment_system"] == rank["provider"] }
        attempted_names << provider["payment_system"]
        outcome = perform(provider, operation, state, index + 1)
        if outcome.result == "approved"
          state.commit(provider["payment_system"], operation["amount"])
          selected, selected_outcome = provider, outcome
          attempts << selected_attempt(provider, outcome, rank, "highest_combined_score")
          break
        elsif outcome.result == "expired" && @timeout_mode == "hold_until_status"
          if outcome.status_check_result == "rejected"
            state.rollback(provider["payment_system"], operation["amount"])
            attempts << failed_attempt(provider, outcome, "provider_expired_status_rejected", rank)
          else
            state.commit(provider["payment_system"], operation["amount"]) if outcome.status_check_result == "approved"
            selected, selected_outcome = provider, outcome
            attempts << selected_attempt(provider, outcome, rank, "timeout_held_until_status")
            break
          end
        else
          state.rollback(provider["payment_system"], operation["amount"])
          reason = outcome.result == "expired" ? "provider_expired" : "provider_rejected"
          attempts << failed_attempt(provider, outcome, reason, rank)
        end
      end

      unless selected
        fallback_evaluation = @constraints.evaluate(provider: fallback, operation:, state:)
        unless fallback_evaluation["eligible"]
          issue = fallback_evaluation["failures"].first
          raise Error, "fallback #{@fallback_name} недоступен для #{operation['operation_id']}: #{issue['code']}"
        end
        outcome = perform(fallback, operation, state, ranking.length + 1)
        if outcome.result == "approved"
          state.commit(fallback["payment_system"], operation["amount"])
        elsif outcome.result == "expired" && @timeout_mode == "hold_until_status"
          state.commit(fallback["payment_system"], operation["amount"]) if outcome.status_check_result == "approved"
        else
          state.rollback(fallback["payment_system"], operation["amount"])
        end
        selected, selected_outcome = fallback, outcome
        attempts << selected_attempt(fallback, outcome, nil, "external_pool_exhausted")
        evaluations[fallback["payment_system"]] = fallback_evaluation
      end

      add_unattempted_eligible(attempts, ranking, attempted_names, selected["payment_system"])
      state.record_selected(selected["payment_system"], operation["amount"])
      after = state.snapshot(at:)
      selected_rank = ranking.find { |row| row["provider"] == selected["payment_system"] }
      {
        "operation_id" => operation["operation_id"],
        "selected_provider" => selected["payment_system"],
        "attempts" => attempts,
        "simulated_result" => selected_outcome.result,
        "latency_sec" => selected_outcome.latency_sec,
        "strategy" => @preset,
        "score" => selected_rank&.dig("combined_score"),
        "score_breakdown" => selected_rank&.dig("score_breakdown") || {},
        "eligible_pool" => eligible.map { |provider| provider["payment_system"] },
        "ranking" => ranking,
        "constraint_matrix" => evaluations,
        "conflicts" => conflicts(ranking),
        "tie_break_rule" => "combined_score → policy_priority → provider.priority → payment_system",
        "state_before" => before,
        "state_after" => after,
        "fallback_used" => selected["payment_system"] == @fallback_name,
        "status_check_result" => selected_outcome.status_check_result,
        "decision_time_ms" => 0.0
      }.compact
    end

    def perform(provider, operation, state, attempt)
      state.reserve(provider["payment_system"], operation["amount"], Time.iso8601(operation["created_at"]))
      @simulator.call(operation:, provider:, attempt:)
    end

    def hard_failure_attempts(providers, evaluations)
      providers.filter_map do |provider|
        failure = evaluations.dig(provider["payment_system"], "failures")&.first
        next unless failure
        { "provider" => provider["payment_system"], "decision" => "skipped", "reason" => failure["code"],
          "details" => failure["explanation"], "actual" => failure["actual"], "threshold" => failure["threshold"] }
      end
    end

    def selected_attempt(provider, outcome, rank, reason)
      { "provider" => provider["payment_system"], "decision" => "selected", "reason" => reason,
        "result" => outcome.result, "latency_sec" => outcome.latency_sec, "sequence" => rank&.dig("rank"),
        "score" => rank&.dig("combined_score"), "status_check_result" => outcome.status_check_result }.compact
    end

    def failed_attempt(provider, outcome, reason, rank)
      { "provider" => provider["payment_system"], "decision" => "skipped", "reason" => reason,
        "result" => outcome.result, "latency_sec" => outcome.latency_sec, "sequence" => rank["rank"],
        "score" => rank["combined_score"], "status_check_result" => outcome.status_check_result }.compact
    end

    def add_unattempted_eligible(attempts, ranking, attempted_names, selected_name)
      ranking.each do |rank|
        next if attempted_names.include?(rank["provider"]) || rank["provider"] == selected_name
        attempts << { "provider" => rank["provider"], "decision" => "skipped", "reason" => "lower_combined_score",
          "details" => "rank #{rank['rank']}, score #{rank['combined_score']}", "score" => rank["combined_score"] }
      end
    end

    def conflicts(ranking)
      return [] if ranking.length < 2
      policies = ranking.flat_map { |row| row["score_breakdown"].keys }.uniq
      winners = policies.to_h do |name|
        best = ranking.max_by { |row| row["score_breakdown"].dig(name, "normalized_value") || -1 }
        [ name, best["provider"] ]
      end
      winners.values.uniq.length > 1 ? [ { "code" => "policy_winners_disagree", "winners" => winners,
        "resolution" => "weighted combined score and deterministic tie-break" } ] : []
    end

    def monotonic
      @clock.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
