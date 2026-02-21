# frozen_string_literal: true

class AddOriginToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :origin_channel_type, :string
    add_column :sessions, :origin_channel_id, :bigint
    add_column :sessions, :origin_sender, :string

    add_index :sessions, :origin_channel_type
    add_index :sessions, [:origin_channel_type, :origin_sender]
  end
end
