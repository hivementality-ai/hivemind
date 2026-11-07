# frozen_string_literal: true

class CreateAudioNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :audio_notes do |t|
      t.references :session, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.references :knowledge_document, foreign_key: { on_delete: :nullify }
      t.string :filename
      t.string :content_type
      t.integer :byte_size
      t.string :status, null: false, default: "queued"
      t.boolean :keep_recording, null: false, default: false
      t.text :transcript
      t.text :notes
      t.text :error
      t.timestamps
    end
  end
end
