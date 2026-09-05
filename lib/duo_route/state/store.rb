# frozen_string_literal: true

module DuoRoute
  module State
    class Store
      attr_reader :providers, :selected_counts, :selected_volumes

      def initialize(providers)
        @providers = providers.to_h do |provider|
          [ provider.fetch("payment_system"), {
            "daily_approved_amount" => provider["daily_approved_amount"].to_f,
            "in_progress_count" => provider["in_progress_count"].to_i,
            "in_progress_amount" => provider["in_progress_amount"].to_f,
            "rpm_timestamps" => []
          } ]
        end
        @selected_counts = Hash.new(0)
        @selected_volumes = Hash.new(0.0)
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
        state["in_progress_amount"] += amount
        state["rpm_timestamps"] << at.to_f
      end

      def rollback(provider_name, amount)
        state = @providers.fetch(provider_name)
        state["in_progress_count"] = [ state["in_progress_count"] - 1, 0 ].max
        state["in_progress_amount"] = [ state["in_progress_amount"] - amount, 0.0 ].max
      end

      def commit(provider_name, amount)
        rollback(provider_name, amount)
        @providers.fetch(provider_name)["daily_approved_amount"] += amount
      end

      def record_selected(provider_name, amount)
        @selected_counts[provider_name] += 1
        @selected_volumes[provider_name] += amount
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
        state["rpm_timestamps"].select! { |timestamp| timestamp > cutoff }
      end

      def clean(number)
        number == number.to_i ? number.to_i : number.round(2)
      end
    end
  end
end
