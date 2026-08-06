class CreateDesktopPairingCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :desktop_pairing_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :device_name, null: false
      t.string :code, null: false
      t.string :code_challenge, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :desktop_pairing_codes, :code, unique: true
  end
end
