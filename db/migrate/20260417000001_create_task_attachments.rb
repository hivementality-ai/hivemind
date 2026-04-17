# frozen_string_literal: true

class CreateTaskAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :task_attachments do |t|
      t.references :task, null: false, foreign_key: true, index: true
      t.string :title,        null: false
      t.string :url
      t.string :content_type
      t.string :uploaded_by
      t.timestamps
    end
  end
end
