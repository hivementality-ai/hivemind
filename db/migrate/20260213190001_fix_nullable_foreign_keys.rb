class FixNullableForeignKeys < ActiveRecord::Migration[8.1]
  def change
    # vault_entries.agent_id should be nullable (nil = global scope)
    change_column_null :vault_entries, :agent_id, true
  end
end
