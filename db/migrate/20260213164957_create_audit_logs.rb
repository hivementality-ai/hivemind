class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.string :actor_type
      t.string :actor_id
      t.string :action
      t.string :resource
      t.jsonb :metadata

      t.timestamps
    end
  end
end
