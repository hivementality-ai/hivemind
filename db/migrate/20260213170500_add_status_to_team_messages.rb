# frozen_string_literal: true

class AddStatusToTeamMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :team_messages, :status, :string, default: "pending"
    add_column :team_messages, :completed_at, :datetime

    add_index :team_messages, :status
  end
end
