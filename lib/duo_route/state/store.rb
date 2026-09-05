# frozen_string_literal: true

module DuoRoute
  module State
    class Store
      attr_reader :providers, :selected_counts, :selected_volumes

      def initialize(providers, snapshot_at: nil)
        @day = snapshot_at && Time.iso8601(snapshot_at).utc.to_date
        @daily_history = {}
        @reservations = Hash.new(0)
        @providers = providers.to_h do |provider|
          [ provider.fetch("payment_system"), {
            "daily_approved_amount" => Money.decimal(provider["daily_approved_amount"]),
            "in_progress_count" => provider["in_progress_count"].to_i,
            "in_progress_amount" => Money.decimal(provider["in_progress_amount"]),
            "rpm_timestamps" => []
          } ]
        end
        @selected_counts = Hash.new(0)
        @selected_volumes = Hash.new(BigDecimal("0"))
      end

      attr_reader :day, :daily_history

      def advance(at)
        day = at.utc.to_date
        raise Error, "время состояния не может двигаться назад" if @day && day < @day
        if @day && day != @day
          @daily_history[@day.iso8601] = snapshot(at:)
          @providers.each_value { |state| state["daily_approved_amount"] = BigDecimal("0") }
        end
        @day = day
        @providers.each_key { |name| prune_rpm(name, at) }
      end

      def for(provider_name, at: nil)
        prune_rpm(provider_name, at) if at
        @providers.fetch(provider_name)
      end

      def rpm(provider_name, at)
        prune_rpm(provider_name, at)
        @providers.fetch(provider_name)["rpm_timestamps"].length
      end

      def reserve(provider_name, amount, at)
        state = self.for(provider_name, at:)
        state["in_progress_count"] += 1
        state["in_progress_amount"] += Money.decimal(amount)
        state["rpm_timestamps"] << at.to_f
        @reservations[[ provider_name, Money.decimal(amount) ]] += 1
      end

      def rollback(provider_name, amount)
        key = [ provider_name, Money.decimal(amount) ]
        return false if @reservations[key].zero?
        @reservations[key] -= 1
        @reservations.delete(key) if @reservations[key].zero?
        state = @providers.fetch(provider_name)
        state["in_progress_count"] = [ state["in_progress_count"] - 1, 0 ].max
        state["in_progress_amount"] -= Money.decimal(amount)
        true
      end

      def commit(provider_name, amount)
        raise Error, "commit без активного reserve: #{provider_name}" unless rollback(provider_name, amount)
        @providers.fetch(provider_name)["daily_approved_amount"] += Money.decimal(amount)
      end

      def record_selected(provider_name, amount)
        @selected_counts[provider_name] += 1
        @selected_volumes[provider_name] += Money.decimal(amount)
      end

      def selected_total
        @selected_counts.values.sum
      end

      def selected_volume_total
        @selected_volumes.values.sum
      end

      def snapshot(at: nil)
        @providers.transform_values do |state|
          {
            "daily_approved_amount" => clean(state["daily_approved_amount"]),
            "in_progress_count" => state["in_progress_count"],
            "in_progress_amount" => clean(state["in_progress_amount"]),
            "requests_last_minute" => state["rpm_timestamps"].count { |timestamp| at.nil? || timestamp > at.to_f - 60 }
          }
        end
      end

      private

      def prune_rpm(provider_name, at)
        state = @providers.fetch(provider_name)
        cutoff = at.to_f - 60
        timestamps = state["rpm_timestamps"]
        first_live = timestamps.bsearch_index { |timestamp| timestamp > cutoff } || timestamps.length
        timestamps.shift(first_live) if first_live.positive?
      end

      def clean(number)
        Money.number(number)
      end
    end
  end
end
