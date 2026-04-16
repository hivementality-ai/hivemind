# frozen_string_literal: true

class AddParentIdToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :parent, foreign_key: { to_table: :tasks }, null: true, index: true
  end
end
