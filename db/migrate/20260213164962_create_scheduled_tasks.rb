class CreateScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_tasks do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name
      t.string :schedule
      t.string :job_class
      t.jsonb :params
      t.boolean :enabled
      t.datetime :last_run_at
      t.datetime :next_run_at

      t.timestamps
    end
  end
end
