class CreateTeamMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :team_messages do |t|
      t.references :from_agent, null: false, foreign_key: { to_table: :agents }
      t.references :to_agent, foreign_key: { to_table: :agents }
      t.references :team, null: false, foreign_key: true
      t.text :content
      t.string :message_type
      t.jsonb :metadata

      t.timestamps
    end
  end
end
