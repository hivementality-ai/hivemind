# frozen_string_literal: true

class AddRequirementsToTools < ActiveRecord::Migration[8.0]
  def change
    add_column :tools, :requirements, :jsonb, default: {}, null: false
  end
end
