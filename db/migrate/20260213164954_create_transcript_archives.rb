class CreateTranscriptArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_archives do |t|
      t.references :session, null: false, foreign_key: true
      t.jsonb :transcript
      t.datetime :archived_at

      t.timestamps
    end
  end
end
