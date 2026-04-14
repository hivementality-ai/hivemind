# frozen_string_literal: true

class CreateTaskHooks < ActiveRecord::Migration[8.0]
  def change
    create_table :task_hooks do |t|
      t.references :task, foreign_key: true, null: true
      t.references :task_template, foreign_key: true, null: true
      t.references :skill, foreign_key: true, null: false
      t.string :trigger, null: false
      t.string :on_status, null: false
      t.integer :position, null: false, default: 0
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :task_hooks, [ :task_id, :trigger, :on_status ]
    add_index :task_hooks, [ :task_template_id, :trigger, :on_status ]
  end
end
