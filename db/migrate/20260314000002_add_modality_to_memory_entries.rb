# frozen_string_literal: true

class AddModalityToMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :memory_entries, :modality, :string, default: "text", null: false
  end
end
