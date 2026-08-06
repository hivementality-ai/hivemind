# frozen_string_literal: true

# The TeamMessage-based delegation path (Agents::Orchestrate, Agents::Delegate,
# Agents::Communicate, AgentTaskJob) had no live callers — delegation runs
# through SubAgentTask/SubAgentJob. Drop the orphaned table.
class DropTeamMessages < ActiveRecord::Migration[8.1]
  def up
    drop_table :team_messages
  end

  def down
    create_table :team_messages do |t|
      t.datetime :completed_at
      t.text :content
      t.bigint :from_agent_id, null: false
      t.string :message_type
      t.jsonb :metadata
      t.string :status, default: "pending"
      t.bigint :team_id, null: false
      t.bigint :to_agent_id
      t.timestamps

      t.index :from_agent_id
      t.index :status
      t.index %i[team_id created_at]
      t.index :team_id
      t.index :to_agent_id
    end

    add_foreign_key :team_messages, :agents, column: :from_agent_id
    add_foreign_key :team_messages, :agents, column: :to_agent_id
    add_foreign_key :team_messages, :teams
  end
end
