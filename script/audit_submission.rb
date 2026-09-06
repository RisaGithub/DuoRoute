#!/usr/bin/env ruby
# frozen_string_literal: true

# Deliberately standalone: stdlib only, no routing code or Rails.
require "json"
require "bigdecimal"
require "time"
require "digest"
require "optparse"

class SubmissionAudit
  class Invalid < StandardError; end
  class UniqueObject < Hash
    def []=(key, value)
      raise Invalid, "duplicate JSON object key" if key?(key)
      super
    end
  end

  RESULTS = %w[approved rejected expired].freeze
  SENSITIVE = /\A(?:pan|card_number|cvv|cvc|password|secret|api_key|access_token|authorization|phone|email|recipient|requisites)\z/i
  LIMITATIONS = [
    "Checks recorded outcomes, not the truth of simulated provider responses or optimality of scoring.",
    "RPM starts empty at snapshot; external completions and pre-snapshot requests are not observable.",
    "Resolved configuration is declared evidence, not authenticated input; use --config to pin it.",
    "Sensitive-field screening is heuristic; arbitrary secrets embedded in free text cannot be proven absent."
  ].freeze

  def self.run(argv, out: $stdout, err: $stderr)
    paths = {}
    parser = OptionParser.new do |opts|
      %w[providers operations decisions report config].each { |name| opts.on("--#{name} PATH") { |value| paths[name] = value } }
    end
    parser.parse!(argv)
    raise Invalid, "unexpected arguments" unless argv.empty?
    %w[providers operations decisions report].each { |key| raise Invalid, "missing --#{key}" unless paths[key] }
    inputs = paths.transform_values { |path| JSON.parse(File.read(path), allow_nan: false, object_class: UniqueObject) }
    audit = new(**inputs.transform_keys(&:to_sym))
    audit.call
    out.puts "AUDIT PASS: #{audit.checks} checks; coverage, attempts, ten constraints, state and report reconciled."
    LIMITATIONS.each { |line| out.puts "Scope: #{line}" }
    0
  rescue Invalid, JSON::ParserError, JSON::GeneratorError, OptionParser::ParseError, SystemCallError, KeyError, TypeError, ArgumentError, NoMethodError => e
    # Do not print parser excerpts: they may contain sensitive input.
    err.puts "AUDIT FAIL: #{e.is_a?(Invalid) ? e.message : e.class.name}"
    2
  end

  attr_reader :checks

  def initialize(providers:, operations:, decisions:, report:, config: nil)
    @source, @operations, @decisions, @report, @pinned_config = providers, operations, decisions, report, config
    @checks = 0
  end

  def call
    check(@source.is_a?(Hash) && @source["providers"].is_a?(Array), "providers root")
    check(@operations.is_a?(Array) && @operations.any?, "operations root/empty queue")
    check(@decisions.is_a?(Array), "decisions root")
    check(@report.is_a?(Hash), "report root")
    scan(@decisions, "decisions")
    scan(@report, "report")
    manifest = @report.fetch("reproducibility")
    @config = manifest.fetch("resolved_configuration")
    equal(@config, @pinned_config, "pinned config") if @pinned_config
    check([ digest(@source), digest(normalize_input(@source)) ].include?(manifest["providers_sha256"]), "providers digest")
    check([ digest(@operations), digest(normalize_input(@operations)) ].include?(manifest["operations_sha256"]), "operations digest")
    equal(digest(@config), manifest["config_sha256"], "config digest")
    @fallback = @config.fetch("routing").fetch("fallback_provider", "spacepayments")
    @timeout = @config.fetch("routing").fetch("timeout_mode", "fallback_on_timeout")
    check(%w[fallback_on_timeout hold_until_status].include?(@timeout), "timeout mode")
    @providers = @source["providers"].to_h do |provider|
      name = provider.fetch("payment_system")
      [ name, provider.merge(@config.fetch("provider_overrides", {}).fetch(name, {})) ]
    end
    equal(@providers.size, @source["providers"].size, "unique providers")
    check(@providers.key?(@fallback), "fallback exists")
    ordered = @operations.each_with_index.sort_by { |op, index| [ Time.iso8601(op.fetch("created_at")), index ] }.map(&:first)
    ids = ordered.map { |op| op.fetch("operation_id") }
    check(ids.all? { |id| id.is_a?(String) && !id.strip.empty? } && ids.uniq == ids, "unique operation_id")
    equal(@decisions.map { |row| row.fetch("operation_id") }, ids, "coverage and chronological order")
    @state = @providers.transform_values do |p|
      { "daily_approved_amount" => decimal(p.fetch("daily_approved_amount")),
        "in_progress_count" => p.fetch("in_progress_count"), "in_progress_amount" => decimal(p.fetch("in_progress_amount")),
        "requests_last_minute" => 0 }
    end
    @requests = @providers.transform_values { [] }
    @day = Time.iso8601(@source.fetch("snapshot_at")).utc.to_date
    @daily_history = {}
    @eligible_counts = Hash.new(0)
    @eligible_amounts = Hash.new { |h, k| h[k] = BigDecimal("0") }
    @counts = Hash.new(0)
    @amounts = Hash.new { |h, k| h[k] = BigDecimal("0") }
    ordered.zip(@decisions).each { |operation, decision| audit_decision(operation, decision) }
    audit_report
    true
  end

  private

  def audit_decision(op, row)
    id = op.fetch("operation_id")
    at = Time.iso8601(op.fetch("created_at"))
    check(at >= Time.iso8601(@source.fetch("snapshot_at")), "#{id}: before snapshot")
    @requests.each do |name, times|
      times.reject! { |t| t <= at - 60 }
      @state[name]["requests_last_minute"] = times.size
    end
    if at.utc.to_date != @day
      @daily_history[@day.iso8601] = snapshot
      @state.each_value { |s| s["daily_approved_amount"] = BigDecimal("0") }
      @day = at.utc.to_date
    end
    equal(row["state_before"], snapshot, "#{id}: state_before") if row.key?("state_before")
    amount = decimal(op.fetch("amount"))
    check(amount.positive?, "#{id}: amount")
    equal(row["amount"], op["amount"], "#{id}: amount") if row.key?("amount")
    name = row.fetch("selected_provider")
    check(@providers.key?(name), "#{id}: unknown selected_provider")
    check(RESULTS.include?(row.fetch("simulated_result")), "#{id}: simulated_result enum")
    attempts = row.fetch("attempts")
    check(attempts.is_a?(Array) && attempts.any?, "#{id}: attempts")
    attempts.each do |a|
      check(a.is_a?(Hash) && @providers.key?(a["provider"]), "#{id}: attempt provider")
      check(%w[selected skipped].include?(a["decision"]), "#{id}: attempts.decision enum")
      check(a["reason"].is_a?(String) && !a["reason"].empty?, "#{id}: attempt reason")
    end
    equal(attempts.map { |a| a["provider"] }.uniq.size, attempts.size, "#{id}: duplicate attempt")
    external_names = @providers.keys - [ @fallback, "spacepayments" ]
    considered = external_names + (name == @fallback ? [ @fallback ] : [])
    equal(attempts.map { |a| a["provider"] }.sort, considered.sort, "#{id}: attempts coverage")
    invoked = attempts.select { |a| a.key?("result") }
    selected = attempts.select { |a| a["decision"] == "selected" }
    equal(selected.size, 1, "#{id}: selected count")
    equal(selected.first["provider"], name, "#{id}: selected provider mismatch")
    equal(selected.first["result"], row["simulated_result"], "#{id}: selected result mismatch")
    equal(invoked.last, selected.first, "#{id}: selected must be last actual attempt")
    eligible = @providers.keys.reject { |n| [ @fallback, "spacepayments" ].include?(n) }.select { |n| allowed?(@providers[n], op) }
    eligible.each { |n| @eligible_counts[n] += 1; @eligible_amounts[n] += amount }
    equal(row["eligible_pool"].sort, eligible.sort, "#{id}: eligible_pool") if row.key?("eligible_pool")
    invoked.each_with_index do |attempt, index|
      provider = attempt["provider"]
      check(RESULTS.include?(attempt["result"]), "#{id}: attempt result enum")
      check(allowed?(@providers[provider], op), "#{id}: hard constraint violation")
      equal(attempt["sequence"], index + 1, "#{id}: attempt sequence") if provider != @fallback || attempt.key?("sequence")
      status = attempt["status_check_result"]
      check(status.nil? || %w[approved rejected].include?(status), "#{id}: status check enum")
      if provider == @fallback
        equal(eligible.sort, invoked.take(index).map { |a| a["provider"] }.sort, "#{id}: early fallback")
      end
      terminal = attempt["result"] == "approved" || (attempt["result"] == "expired" && @timeout == "hold_until_status" && status != "rejected")
      check(!terminal || index == invoked.size - 1, "#{id}: cascade after terminal outcome")
      check(provider == @fallback || terminal || attempt["decision"] == "skipped", "#{id}: premature external selection")
      nonnegative(attempt.fetch("latency_sec"), "#{id}: attempt latency")
      @requests[provider] << at
      state = @state[provider]
      state["requests_last_minute"] += 1
      if attempt["result"] == "approved" || (attempt["result"] == "expired" && @timeout == "hold_until_status" && status == "approved")
        state["daily_approved_amount"] += amount
      elsif attempt["result"] == "expired" && @timeout == "hold_until_status" && status.nil?
        state["in_progress_count"] += 1
        state["in_progress_amount"] += amount
      end
    end
    nonnegative(row.fetch("latency_sec"), "#{id}: latency")
    equal(row["latency_sec"], invoked.sum { |a| a["latency_sec"] }, "#{id}: latency sum")
    equal(row["fallback_used"], name == @fallback, "#{id}: fallback flag") if row.key?("fallback_used")
    equal(row["state_after"], snapshot, "#{id}: state_after") if row.key?("state_after")
    @counts[name] += 1
    @amounts[name] += amount
  end

  # Independent arithmetic, no matrix or eligibility flags trusted.
  def allowed?(p, op)
    s = @state.fetch(p["payment_system"])
    amount = decimal(op["amount"])
    return false unless p["status"] == "active" && p["available_requisites"].positive?
    return false if p["limit_amount_min"] && amount < decimal(p["limit_amount_min"])
    { "limit_amount_max" => amount, "daily_amount_limit" => s["daily_approved_amount"] + amount,
      "in_progress_count_limit" => s["in_progress_count"] + 1, "in_progress_amount_limit" => s["in_progress_amount"] + amount,
      "requests_per_minute_limit" => s["requests_last_minute"] + 1 }.each do |limit, value|
      return false if p[limit] && value > decimal(p[limit])
    end
    banks = p.fetch("banks")
    return false if banks.any? && (p["exclude_banks"] ? banks.include?(op["bank"]) : !banks.include?(op["bank"]))
    p["allow_negative_agreement"] == true || decimal(p["provider_margin_pct"]) <= decimal(p["merchant_margin_pct"])
  end

  def audit_report
    total = @operations.size
    amount = @amounts.values.sum
    equal(@report.fetch("total_operations"), total, "report total_operations")
    equal(decimal(@report.fetch("total_amount")), amount, "report total_amount")
    %w[period recommendations recommendation_details projected_daily_utilization].each { |k| check(@report.key?(k), "report missing #{k}") }
    %w[distribution volume_distribution].each { |k| equal(@report.fetch(k).keys.sort, @providers.keys.sort, "report #{k} providers") }
    @providers.each do |name, provider|
      count = @report["distribution"].fetch(name)
      volume = @report["volume_distribution"].fetch(name)
      equal(count.fetch("count"), @counts[name], "report count")
      equal(decimal(volume.fetch("amount")), @amounts[name], "report volume amount")
      [ [ count, pct(@counts[name], total), provider.fetch("traffic_percentage") ],
       [ volume, pct(@amounts[name], amount), provider["volume_share_pct"] ] ].each do |row, share, target|
        equal(row.fetch("share_pct"), share, "report percentage")
        equal(row.fetch("target_pct"), target, "report target")
        equal(row.fetch("deviation_pp"), target && (share - target).round(2), "report deviation")
      end
      invoked = @decisions.flat_map { |d| d["attempts"] }.select { |a| a["provider"] == name && a.key?("result") }
      expected_performance = { "attempts" => invoked.size, "approved" => invoked.count { |a| a["result"] == "approved" },
        "success_rate_pct" => pct(invoked.count { |a| a["result"] == "approved" }, invoked.size),
        "average_latency_sec" => invoked.empty? ? 0.0 : (invoked.sum { |a| a["latency_sec"] }.fdiv(invoked.size)).round(2),
        "results" => invoked.map { |a| a["result"] }.tally }
      equal(@report.fetch("provider_performance").fetch(name), expected_performance, "report provider performance")
      utilization = @report.fetch("capacity_utilization").fetch(name)
      %w[daily_approved_amount in_progress_count in_progress_amount requests_last_minute].zip(%w[daily_used in_progress_count_end in_progress_amount_end requests_last_minute]).each do |state_key, report_key|
        equal(decimal(utilization.fetch(report_key)), decimal(@state[name][state_key]), "report final state #{report_key}")
      end
      used = @state[name]["daily_approved_amount"]
      limit = provider["daily_amount_limit"]
      percentage = limit.nil? || limit.zero? ? nil : pct(used, limit)
      equal(utilization.fetch("daily_utilization_pct"), percentage, "report daily utilization percentage")
      equal(utilization.fetch("daily_limit"), limit, "report daily limit")
      projected = @report.fetch("projected_daily_utilization").fetch(name)
      equal(decimal(projected.fetch("used")), used, "report projected daily used")
      equal(projected.fetch("limit"), limit, "report projected daily limit")
      equal(projected.fetch("utilization_pct"), percentage, "report projected utilization percentage")
      %w[in_progress_count in_progress_amount].each do |field|
        cap = provider["#{field}_limit"]
        expected_pct = cap.nil? || cap.zero? ? nil : pct(@state[name][field], cap)
        equal(utilization.fetch("#{field}_utilization_pct"), expected_pct, "report #{field} utilization percentage")
        equal(utilization.fetch("#{field}_limit"), cap, "report #{field} limit")
      end
    end
    times = @operations.map { |op| Time.iso8601(op["created_at"]) }
    period = times.map(&:to_date).uniq.one? ? times.first.to_date.iso8601 : "#{times.min.iso8601}/#{times.max.iso8601}"
    equal(@report.fetch("period"), period, "report period")
    results = @decisions.map { |row| row["simulated_result"] }.tally
    equal(@report.fetch("results"), results, "report results")
    equal(@report.fetch("approval_rate_pct"), pct(results.fetch("approved", 0), total), "report approval rate")
    equal(@report.fetch("fallback_rate_pct"), pct(@counts[@fallback], total), "report fallback rate")
    equal(@report.fetch("average_latency_sec"), (@decisions.sum { |row| row["latency_sec"] }.fdiv(total)).round(2), "report average latency")
    skips = @decisions.flat_map { |row| row["attempts"] }.select { |a| a["decision"] == "skipped" }.map { |a| a["reason"] }.tally
    equal(@report.fetch("skip_reasons"), skips, "report skip reasons")
    equal(@report.fetch("daily_state_date"), @day.iso8601, "report final day")
    equal(@report.fetch("daily_state_history"), @daily_history.merge(@day.iso8601 => snapshot), "report daily history")
    @report.fetch("goal_feasibility", {}).each do |name, row|
      check(@providers.key?(name), "feasibility provider")
      equal(row.fetch("eligible_operations"), @eligible_counts[name], "feasibility count")
      equal(decimal(row.fetch("eligible_amount")), @eligible_amounts[name], "feasibility amount")
      equal(row.fetch("observed_upper_share_pct"), pct(@eligible_counts[name], total), "feasibility upper bound")
      equal(row.fetch("actual_count_share_pct"), pct(@counts[name], total), "feasibility actual")
      equal(row.fetch("target_count_share_pct"), @providers[name]["traffic_percentage"], "feasibility target")
    end
  end

  def snapshot
    @state.transform_values { |s| s.transform_values { |v| v.is_a?(BigDecimal) ? (v.frac.zero? ? v.to_i : v.to_f) : v } }
  end

  def scan(value, path)
    case value
    when Hash
      value.each do |key, item|
        check(!key.match?(SENSITIVE), "#{path}: sensitive field (value withheld)")
        scan(item, "#{path}.#{key}")
      end
    when Array then value.each_with_index { |item, index| scan(item, "#{path}[#{index}]") }
    when Numeric then check(value.finite?, "#{path}: nonfinite number")
    end
  end

  def normalize_input(value)
    case value
    when Hash then value.transform_values { |item| normalize_input(item) }
    when Array then value.map { |item| normalize_input(item) }
    when Float then value == value.to_i ? value.to_i : value
    else value
    end
  end

  def canonical(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [ key, canonical(value[key]) ] }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def digest(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  def decimal(value)
    check(value.is_a?(Numeric) && value.finite?, "monetary field must be a finite JSON number")
    BigDecimal(value.to_s)
  end
  def pct(value, total) = total.zero? ? 0.0 : (value.to_f / total * 100).round(2)
  def nonnegative(value, path) = check(value.is_a?(Numeric) && value.finite? && value >= 0, path)
  def equal(actual, expected, path) = check(actual == expected, path)

  def check(condition, path)
    @checks += 1
    raise Invalid, path unless condition
  end
end

exit SubmissionAudit.run(ARGV) if $PROGRAM_NAME == __FILE__
