# frozen_string_literal: true

class AddArtifactsToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :artifacts, :jsonb, null: false, default: []
  end
end
