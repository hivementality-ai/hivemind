# frozen_string_literal: true

class CreateInboundAndOutboundMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :inbound_messages do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :sender, null: false
      t.text :content
      t.jsonb :metadata, null: false, default: {}
      t.datetime :received_at, null: false

      t.timestamps
    end

    create_table :outbound_messages do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :recipient, null: false
      t.text :content
      t.jsonb :metadata, null: false, default: {}
      t.datetime :sent_at, null: false
      t.string :status, default: "sent"

      t.timestamps
    end

    add_index :inbound_messages, [:channel_id, :external_id], unique: true
    add_index :inbound_messages, :received_at
    add_index :outbound_messages, :sent_at
  end
end
