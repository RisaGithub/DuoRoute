# frozen_string_literal: true

class MethodologyController < ApplicationController
  def show
    @reason_codes = %w[provider_inactive amount_below_minimum amount_exceeds_limit daily_amount_limit_exceeded
      in_progress_count_limit_exceeded in_progress_amount_limit_exceeded bank_not_in_list bank_excluded
      negative_margin_not_allowed no_available_requisites rate_limit_exceeded provider_rejected provider_expired]
  end
end
