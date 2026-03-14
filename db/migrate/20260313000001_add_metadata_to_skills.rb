# frozen_string_literal: true

class AddMetadataToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :metadata, :jsonb, null: false, default: {}
  end
end
