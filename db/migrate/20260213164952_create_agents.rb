class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name
      t.string :role
      t.references :team, null: false, foreign_key: true
      t.jsonb :model_config
      t.jsonb :tools_config
      t.integer :status
      t.string :workspace_path
      t.text :system_prompt

      t.timestamps
    end
  end
end
