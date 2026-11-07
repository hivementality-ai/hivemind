# frozen_string_literal: true

class AddPinnedToMemoryEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :memory_entries, :pinned, :boolean, default: false, null: false
  end
end
