#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/duo_route"

count = Integer(ARGV.fetch(0, "10000"))
providers_count = Integer(ARGV.fetch(1, "20"))
history_count = Integer(ARGV.fetch(2, "100000"))
bundle = DuoRoute::Generators::Scenario.new(name: "stress", operations: count, providers: providers_count, seed: 42).call
headers = %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
history = Array.new(history_count) do |i|
  row = headers.zip(bundle["history"][i % bundle["history"].length]).to_h
  row.merge("operation_id" => "benchmark_history_#{i}")
end
config = DuoRoute::Input::Loader.config_file(File.expand_path("../config/routing/default.yml", __dir__))
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = DuoRoute::Runner.new(providers_data: bundle["providers"], operations: bundle["operations"], history:, config:, seed: 42).call
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

# Independent numerical invariants, checked for every actual external attempt.
checks = 0
provider_map = bundle["providers"]["providers"].to_h { |provider| [ provider["payment_system"], provider ] }
result.decisions.zip(bundle["operations"]).each do |decision, operation|
  raise "duplicate attempt" unless decision["attempts"].map { |attempt| attempt["provider"] }.uniq.length == decision["attempts"].length
  decision["attempts"].select { |attempt| attempt.key?("result") }.each do |attempt|
    name = attempt["provider"]
    provider = provider_map.fetch(name)
    before = decision["state_before"].fetch(name)
    amount = DuoRoute::Money.decimal(operation["amount"])
    raise "inactive" unless provider["status"] == "active"
    raise "daily limit" if provider["daily_amount_limit"] && DuoRoute::Money.decimal(before["daily_approved_amount"]) + amount > provider["daily_amount_limit"]
    raise "count limit" if provider["in_progress_count_limit"] && before["in_progress_count"] + 1 > provider["in_progress_count_limit"]
    raise "amount limit" if provider["in_progress_amount_limit"] && DuoRoute::Money.decimal(before["in_progress_amount"]) + amount > provider["in_progress_amount_limit"]
    raise "rpm limit" if provider["requests_per_minute_limit"] && before["requests_last_minute"] + 1 > provider["requests_per_minute_limit"]
    raise "minimum" if provider["limit_amount_min"] && amount < provider["limit_amount_min"]
    raise "maximum" if provider["limit_amount_max"] && amount > provider["limit_amount_max"]
    raise "margin" if !provider["allow_negative_agreement"] && provider["provider_margin_pct"] > provider["merchant_margin_pct"]
    raise "requisites" unless provider["available_requisites"].positive?
    checks += 9
  end
  raise "latency" unless decision["latency_sec"] == decision["attempts"].sum { |attempt| attempt.fetch("latency_sec", 0) }
  decision["state_after"].each_value do |state|
    raise "negative state" if state.values.any?(&:negative?)
    checks += 4
  end
end

store = DuoRoute::State::Store.new([ provider_map.values.first ])
name = provider_map.keys.first
at = Time.iso8601(bundle["operations"].first["created_at"])
rpm_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100_000.times { store.reserve(name, 0.01, at); store.rollback(name, 0.01) }
raise "RPM lost" unless store.rpm(name, at) == 100_000
raise "RPM did not expire" unless store.rpm(name, at + 60).zero?
rpm_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - rpm_started
cpu, = Open3.capture2("sysctl", "-n", "machdep.cpu.brand_string")
ram, = Open3.capture2("sysctl", "-n", "hw.memsize")
rss, = Open3.capture2("ps", "-o", "rss=", "-p", Process.pid.to_s)
puts DuoRoute.pretty_json("operations" => count, "external_providers" => providers_count, "history_rows" => history_count,
  "seconds" => elapsed.round(3), "operations_per_second" => (count / elapsed).round(2), "rss_after_kib" => rss.to_i,
  "rpm_100000_seconds" => rpm_elapsed.round(3), "invariant_checks" => checks, "seed" => 42,
  "ruby" => RUBY_DESCRIPTION, "cpu" => cpu.strip, "ram_bytes" => ram.to_i,
  "daily_state_dates" => result.report["daily_state_history"].keys, "note" => "Local observation, not an SLA; /usr/bin/time -l records peak RSS separately")
