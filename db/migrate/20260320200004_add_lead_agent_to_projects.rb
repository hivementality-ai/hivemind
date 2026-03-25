# frozen_string_literal: true

class AddLeadAgentToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :lead_agent, foreign_key: { to_table: :agents }, null: true
  end
end
