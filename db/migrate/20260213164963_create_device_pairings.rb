class CreateDevicePairings < ActiveRecord::Migration[8.1]
  def change
    create_table :device_pairings do |t|
      t.string :name
      t.string :device_id
      t.string :device_type
      t.string :token_digest
      t.integer :status
      t.datetime :approved_at
      t.jsonb :metadata

      t.timestamps
    end
  end
end
