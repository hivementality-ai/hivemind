# frozen_string_literal: true

class AddSkillTiersAndTags < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :tier, :string, null: false, default: "manual"
    add_column :skills, :tags, :text, array: true, default: []
    add_column :skills, :trigger_patterns, :text, array: true, default: []

    add_index :skills, :tier
    add_index :skills, :tags, using: :gin
  end
end
