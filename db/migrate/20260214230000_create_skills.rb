# frozen_string_literal: true

class CreateSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :skills do |t|
      t.string :name, null: false
      t.text :description
      t.text :content, null: false
      t.string :category
      t.boolean :enabled, default: true, null: false
      t.boolean :builtin, default: false, null: false
      t.timestamps
    end

    add_index :skills, :name, unique: true
    add_index :skills, :enabled

    create_table :agent_skills do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :skill, null: false, foreign_key: true
      t.timestamps
    end

    add_index :agent_skills, [ :agent_id, :skill_id ], unique: true
  end
end
