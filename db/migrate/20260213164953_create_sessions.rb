class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.string :session_key
      t.references :agent, null: false, foreign_key: true
      t.string :title
      t.jsonb :transcript
      t.jsonb :metadata
      t.bigint :input_tokens
      t.bigint :output_tokens
      t.bigint :total_tokens
      t.integer :status
      t.datetime :last_activity_at

      t.timestamps
    end
  end
end
