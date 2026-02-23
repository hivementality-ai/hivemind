# frozen_string_literal: true

class AddMemoryTypeAndImportanceToMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :memory_entries, :memory_type, :string, default: "episodic", null: false
    add_column :memory_entries, :importance, :float, default: 0.5, null: false
    add_column :memory_entries, :consolidated, :boolean, default: false, null: false
    add_column :memory_entries, :last_accessed_at, :datetime

    add_index :memory_entries, :memory_type
    add_index :memory_entries, :importance
    add_index :memory_entries, :consolidated
    add_index :memory_entries, [:agent_id, :memory_type]
  end
end
