# frozen_string_literal: true

class AddArchivedAtToTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :tasks, :archived_at, :datetime, null: true, default: nil
    add_index  :tasks, :archived_at
  end
end
