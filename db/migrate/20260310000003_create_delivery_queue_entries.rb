# frozen_string_literal: true

class CreateDeliveryQueueEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_queue_entries do |t|
      t.references :channel, null: false, foreign_key: true
      t.string     :recipient, null: false
      t.text       :content, null: false
      t.jsonb      :options, default: {}
      t.string     :status, default: "pending", null: false
      t.integer    :attempts, default: 0, null: false
      t.integer    :max_attempts, default: 5, null: false
      t.datetime   :next_attempt_at
      t.datetime   :sent_at
      t.text       :last_error
      t.references :agent, foreign_key: true
      t.references :session, foreign_key: true
      t.timestamps
    end

    add_index :delivery_queue_entries, [ :status, :next_attempt_at ]
  end
end
