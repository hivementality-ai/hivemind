# frozen_string_literal: true

class AddTeamIdToUsageRecords < ActiveRecord::Migration[8.1]
  def change
    add_reference :usage_records, :team, foreign_key: true, null: true
    add_index :usage_records, [:team_id, :created_at]
  end
end
