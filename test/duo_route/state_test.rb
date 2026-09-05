# frozen_string_literal: true

require "test_helper"

class StateTest < ActiveSupport::TestCase
  test "reserve commit and rollback never make counters negative" do
    store = state_for([ provider ])
    at = Time.iso8601(operation["created_at"])
    store.reserve("alpha", 500, at)
    assert_equal 1, store.for("alpha")["in_progress_count"]
    assert_equal 500, store.for("alpha")["in_progress_amount"]
    assert_equal 1, store.rpm("alpha", at)
    store.commit("alpha", 500)
    assert_equal 1500, store.for("alpha")["daily_approved_amount"]
    assert_equal 0, store.for("alpha")["in_progress_count"]
    store.rollback("alpha", 500)
    assert_equal 0, store.for("alpha")["in_progress_count"]
    assert_equal 0, store.for("alpha")["in_progress_amount"]
  end

  test "selected queue counters exclude history and count final provider" do
    store = state_for([ provider ])
    store.record_selected("alpha", 250)
    assert_equal 1, store.selected_total
    assert_equal 250, store.selected_volume_total
  end
end
