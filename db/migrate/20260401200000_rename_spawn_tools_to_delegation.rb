# frozen_string_literal: true

class RenameSpawnToolsToDelegation < ActiveRecord::Migration[8.1]
  def up
    # Remove spawn tool (delegate now handles async delegation)
    execute <<~SQL
      DELETE FROM skill_tools WHERE tool_id IN (SELECT id FROM tools WHERE name = 'spawn');
      DELETE FROM agent_tools WHERE tool_id IN (SELECT id FROM tools WHERE name = 'spawn');
      DELETE FROM tool_executions WHERE tool_id IN (SELECT id FROM tools WHERE name = 'spawn');
      DELETE FROM tools WHERE name = 'spawn';
    SQL

    # Rename spawn_status to delegation_status
    execute <<~SQL
      UPDATE tools SET name = 'delegation_status',
                       description = 'Check the status of a delegated task, or list recent delegations.',
                       executor_type = 'delegation_status'
      WHERE name = 'spawn_status';
    SQL

    # Update any agent_tools that referenced spawn_status by name in config
    # (agent_tools reference by tool_id FK so no name update needed there)
  end

  def down
    # Restore spawn_status name
    execute <<~SQL
      UPDATE tools SET name = 'spawn_status',
                       description = 'Check the status of a spawned sub-agent task, or list recent sub-agent tasks.',
                       executor_type = 'spawn_status'
      WHERE name = 'delegation_status';
    SQL

    # Re-create spawn tool
    execute <<~SQL
      INSERT INTO tools (name, description, executor_type, builtin, enabled, parameters_schema, created_at, updated_at)
      VALUES (
        'spawn',
        'Spawn a sub-agent to handle a task in the background.',
        'spawn',
        true,
        true,
        '{"properties":{"agent":{"type":"string","description":"Name of the agent to spawn"},"task":{"type":"string","description":"Task description"}},"required":["agent","task"]}',
        NOW(),
        NOW()
      );
    SQL
  end
end
