# frozen_string_literal: true

class CreateTaskTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :task_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :default_priority, null: false, default: "medium"
      t.jsonb :default_metadata, null: false, default: {}
      t.timestamps
    end

    add_index :task_templates, :name, unique: true
  end
end
