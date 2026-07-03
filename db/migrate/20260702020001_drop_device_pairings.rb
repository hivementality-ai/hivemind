# frozen_string_literal: true

class DropDevicePairings < ActiveRecord::Migration[8.0]
  def up
    drop_table :device_pairings
  end

  def down
    create_table :device_pairings do |t|
      t.string :device_id, null: false
      t.string :device_type, null: false
      t.string :device_name
      t.integer :status, default: 0, null: false
      t.datetime :approved_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :device_pairings, :device_id, unique: true
    add_index :device_pairings, :status
  end
end
