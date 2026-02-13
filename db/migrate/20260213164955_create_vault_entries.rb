class CreateVaultEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :vault_entries do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :namespace
      t.string :key
      t.text :encrypted_value
      t.jsonb :metadata

      t.timestamps
    end
  end
end
