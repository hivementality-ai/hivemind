# frozen_string_literal: true

class AddDepthToSubAgentTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :sub_agent_tasks, :depth, :integer, default: 1, null: false
  end
end
