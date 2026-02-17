class CreateCodingAgentTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :coding_agent_tasks do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: true
      t.text :task
      t.string :cli
      t.string :model
      t.integer :timeout
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.string :task_key
      t.json :process_info
      t.text :output

      t.timestamps
    end
    add_index :coding_agent_tasks, :task_key, unique: true
  end
end
