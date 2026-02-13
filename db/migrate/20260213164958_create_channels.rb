class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string :channel_type
      t.string :name
      t.jsonb :config
      t.boolean :enabled
      t.string :webhook_path

      t.timestamps
    end
  end
end
