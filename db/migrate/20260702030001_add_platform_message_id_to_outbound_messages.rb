# frozen_string_literal: true

class AddPlatformMessageIdToOutboundMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :outbound_messages, :platform_message_id, :string
    add_index :outbound_messages, :platform_message_id
  end
end
