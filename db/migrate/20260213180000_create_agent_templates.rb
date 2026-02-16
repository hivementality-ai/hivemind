# frozen_string_literal: true

class CreateAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :role, null: false
      t.string :category, null: false
      t.text :system_prompt
      t.jsonb :model_config, default: {}, null: false
      t.jsonb :tools_config, default: {}, null: false
      t.text :soul_md
      t.string :icon
      t.boolean :featured, default: false
      t.string :author
      t.string :version, default: "1.0.0"

      t.timestamps
    end

    add_index :agent_templates, :category
    add_index :agent_templates, :featured
  end
end
