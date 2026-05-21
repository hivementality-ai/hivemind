# frozen_string_literal: true

class AddCategoryAndLifecycleToMemoryEntries < ActiveRecord::Migration[8.0]
  CATEGORIES = %w[user_preference project_context decision learned_behavior factual general].freeze
  STATUSES   = %w[active archived superseded].freeze

  def up
    # category enum — what kind of knowledge this memory represents
    add_column :memory_entries, :category, :string, default: "general", null: false

    # lifecycle status — controls whether memory surfaces in search
    add_column :memory_entries, :status, :string, default: "active", null: false

    # superseded_by_id — links a superseded memory to its replacement
    add_column :memory_entries, :superseded_by_id, :bigint, null: true
    add_foreign_key :memory_entries, :memory_entries, column: :superseded_by_id

    # Composite index for filtered queries (the hot path)
    add_index :memory_entries, %i[agent_id category status],
              name: "index_memory_entries_on_agent_id_category_status"

    # Backfill existing rows with safe defaults
    execute <<~SQL
      UPDATE memory_entries
      SET category = 'general', status = 'active'
      WHERE category IS NULL OR status IS NULL;
    SQL

    # Add check constraints to enforce enum values at the DB level
    execute <<~SQL
      ALTER TABLE memory_entries
        ADD CONSTRAINT memory_entries_category_check
          CHECK (category IN ('user_preference', 'project_context', 'decision', 'learned_behavior', 'factual', 'general'));
    SQL

    execute <<~SQL
      ALTER TABLE memory_entries
        ADD CONSTRAINT memory_entries_status_check
          CHECK (status IN ('active', 'archived', 'superseded'));
    SQL
  end

  def down
    execute "ALTER TABLE memory_entries DROP CONSTRAINT IF EXISTS memory_entries_category_check;"
    execute "ALTER TABLE memory_entries DROP CONSTRAINT IF EXISTS memory_entries_status_check;"

    remove_foreign_key :memory_entries, column: :superseded_by_id
    remove_index :memory_entries, name: "index_memory_entries_on_agent_id_category_status"

    remove_column :memory_entries, :superseded_by_id
    remove_column :memory_entries, :status
    remove_column :memory_entries, :category
  end
end
