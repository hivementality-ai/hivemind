# frozen_string_literal: true

class AddSkillsConfigToAgentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_templates, :skills_config, :jsonb, default: {}, null: false
  end
end
