class CreateChannelThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_threads do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.string :external_thread_id, null: false
      t.datetime :last_active_at
      t.timestamps
    end

    add_index :channel_threads, [ :channel_id, :external_thread_id ], unique: true
  end
end
