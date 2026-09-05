# frozen_string_literal: true

module DuoRoute
  module ReasonCodes
    HARD = %w[provider_inactive amount_below_minimum amount_exceeds_limit daily_amount_limit_exceeded
      in_progress_count_limit_exceeded in_progress_amount_limit_exceeded bank_not_in_list bank_excluded
      negative_margin_not_allowed no_available_requisites rate_limit_exceeded].freeze
    FLOW = %w[lower_combined_score provider_rejected provider_expired provider_expired_status_rejected
      highest_combined_score timeout_held_until_status external_pool_exhausted].freeze
    ALL = (HARD + FLOW).freeze
  end
end
