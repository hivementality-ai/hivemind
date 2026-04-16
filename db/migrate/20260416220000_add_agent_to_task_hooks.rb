# frozen_string_literal: true

class AddAgentToTaskHooks < ActiveRecord::Migration[8.0]
  def change
    add_reference :task_hooks, :agent, foreign_key: true, null: true
  end
end
