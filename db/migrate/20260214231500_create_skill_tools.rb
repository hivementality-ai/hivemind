# frozen_string_literal: true

class CreateSkillTools < ActiveRecord::Migration[8.0]
  def change
    create_table :skill_tools do |t|
      t.references :skill, null: false, foreign_key: true
      t.references :tool, null: false, foreign_key: true
      t.timestamps
    end

    add_index :skill_tools, [ :skill_id, :tool_id ], unique: true
  end
end
