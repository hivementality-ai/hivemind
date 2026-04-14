# frozen_string_literal: true

class AddHierarchyToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :title, :string
    add_column :agents, :reports_to_id, :bigint

    add_index :agents, :reports_to_id

    add_foreign_key :agents, :agents,
                    column: :reports_to_id,
                    on_delete: :nullify
  end
end
