# frozen_string_literal: true

class AddCategoryAndLifecycleToMemoryEntries < ActiveRecord::Migration[8.0]
  def up
    add_column :memory_entries, :category, :string, default: "general", null: false
    add_column :memory_entries, :status, :string, default: "active", null: false
    add_column :memory_entries, :superseded_by_id, :bigint, null: true
    add_column :memory_entries, :updated_at, :datetime, null: true

    add_foreign_key :memory_entries, :memory_entries,
                    column: :superseded_by_id,
                    name: "fk_memory_entries_superseded_by"

    add_index :memory_entries, [ :agent_id, :category, :status ],
              name: "idx_memory_entries_agent_category_status"
    add_index :memory_entries, :status,
              name: "idx_memory_entries_status"
    add_index :memory_entries, :category,
              name: "idx_memory_entries_category"

    # Backfill: set updated_at to created_at for all existing rows
    execute <<~SQL
      UPDATE memory_entries
      SET category   = 'general',
          status     = 'active',
          updated_at = created_at
    SQL
  end

  def down
    remove_foreign_key :memory_entries,
                       name: "fk_memory_entries_superseded_by"

    remove_index :memory_entries, name: "idx_memory_entries_agent_category_status"
    remove_index :memory_entries, name: "idx_memory_entries_status"
    remove_index :memory_entries, name: "idx_memory_entries_category"

    remove_column :memory_entries, :updated_at
    remove_column :memory_entries, :superseded_by_id
    remove_column :memory_entries, :status
    remove_column :memory_entries, :category
  end
end
