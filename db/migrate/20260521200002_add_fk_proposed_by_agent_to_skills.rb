# frozen_string_literal: true

class AddFkProposedByAgentToSkills < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :skills, :agents, column: :proposed_by_agent_id, on_delete: :nullify
  end
end
