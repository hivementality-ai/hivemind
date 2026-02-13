# frozen_string_literal: true

class CreateChatAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_attachments do |t|
      t.references :session, null: false, foreign_key: true
      t.string :content_type
      t.string :filename
      t.integer :byte_size
      t.integer :message_index # which transcript message this belongs to
      t.timestamps
    end
  end
end
