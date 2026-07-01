# frozen_string_literal: true

class AddProposalStatusToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :proposal_status, :string, null: true
    add_column :skills, :proposal_notes, :text, null: true
    add_column :skills, :proposed_by_agent_id, :bigint, null: true
    add_column :skills, :proposed_at, :datetime, null: true
    add_column :skills, :proposal_rejected_at, :datetime, null: true
    add_column :skills, :proposal_rejected_by, :bigint, null: true

    add_index :skills, :proposal_status
    add_index :skills, :proposed_by_agent_id
  end
end
