# frozen_string_literal: true

class AddTeamHooksAndOptionalSkill < ActiveRecord::Migration[8.0]
  def change
    add_reference :task_hooks, :team, foreign_key: true, null: true
    add_index :task_hooks, [ :team_id, :trigger, :on_status ]

    change_column_null :task_hooks, :skill_id, true
  end
end
