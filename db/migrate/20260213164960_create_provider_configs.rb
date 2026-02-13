class CreateProviderConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_configs do |t|
      t.string :name, null: false
      t.string :adapter_type, null: false
      t.string :base_url
      t.string :vault_key
      t.jsonb :model_definitions, default: []
      t.boolean :enabled, default: true

      t.timestamps
    end

    add_index :provider_configs, :name, unique: true
  end
end
