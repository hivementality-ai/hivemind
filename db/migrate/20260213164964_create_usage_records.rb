class CreateUsageRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_records do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :session, foreign_key: true
      t.string :provider, null: false
      t.string :llm_model
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :cache_tokens, default: 0
      t.decimal :cost_cents, precision: 10, scale: 4, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :usage_records, :created_at
    add_index :usage_records, [:agent_id, :created_at]
  end
end
