# frozen_string_literal: true

class AddSecurityFieldsToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :declared_capabilities, :jsonb, default: {}, null: false
    add_column :skills, :security_scan_result, :jsonb, default: {}, null: false
    add_column :skills, :source, :string, default: "manual", null: false
    add_column :skills, :source_url, :string
    add_column :skills, :checksum, :string
    add_column :skills, :approved_by, :bigint
    add_column :skills, :approved_at, :datetime

    add_index :skills, :source
    add_index :skills, :checksum
  end
end
