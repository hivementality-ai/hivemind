# frozen_string_literal: true

class AddCustomInstructionsToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :custom_instructions, :text
  end
end
