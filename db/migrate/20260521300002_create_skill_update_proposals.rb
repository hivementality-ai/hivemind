# frozen_string_literal: true

class CreateSkillUpdateProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_update_proposals do |t|
      t.references :skill, null: false, foreign_key: true, index: true
      t.references :proposed_by_agent, null: false, foreign_key: { to_table: :agents }, index: true

      t.text    :proposed_content, null: false
      t.text    :rationale,        null: false  # why the agent thinks this is an improvement
      t.string  :status,           null: false, default: "pending"  # pending | approved | rejected

      # Review outcome
      t.bigint  :reviewed_by_user_id
      t.text    :review_notes
      t.datetime :reviewed_at

      # Snapshot of skill content at time of proposal (for diff rendering)
      t.text    :original_content, null: false

      t.timestamps
    end

    add_index :skill_update_proposals, :status
    add_index :skill_update_proposals, [ :skill_id, :status ]
  end
end
