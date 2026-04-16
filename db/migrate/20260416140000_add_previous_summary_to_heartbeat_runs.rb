# frozen_string_literal: true

class AddPreviousSummaryToHeartbeatRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :heartbeat_runs, :previous_summary, :text
  end
end
