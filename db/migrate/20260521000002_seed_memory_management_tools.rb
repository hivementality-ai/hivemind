# frozen_string_literal: true

class SeedMemoryManagementTools < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO tools (name, description, executor_type, builtin, enabled, parameters_schema, config, created_at, updated_at)
      VALUES
        (
          'memory_store',
          'Store a new memory with a category tag. Use this to deliberately save information for future recall — user preferences, decisions, project context, or learned behaviors.',
          'memory_store',
          true,
          true,
          '{"properties": {"content": {"type": "string", "description": "The memory text to store"}, "category": {"type": "string", "description": "Memory category: user_preference, project_context, decision, learned_behavior, factual, or general (default)", "enum": ["user_preference", "project_context", "decision", "learned_behavior", "factual", "general"]}, "related_memory_id": {"type": "integer", "description": "ID of an existing memory this supersedes — the old memory will be archived and linked to this new one"}}, "required": ["content"]}',
          '{}',
          NOW(),
          NOW()
        ),
        (
          'memory_update',
          'Update an existing memory by ID. Change its content, recategorize it, or change its status (archive it, mark as superseded, or reactivate it).',
          'memory_update',
          true,
          true,
          '{"properties": {"memory_id": {"type": "integer", "description": "ID of the memory to update (returned by memory_store or shown in memory_search results)"}, "content": {"type": "string", "description": "New content for the memory (re-embeds automatically)"}, "category": {"type": "string", "description": "New category", "enum": ["user_preference", "project_context", "decision", "learned_behavior", "factual", "general"]}, "status": {"type": "string", "description": "New status", "enum": ["active", "archived", "superseded"]}}, "required": ["memory_id"]}',
          '{}',
          NOW(),
          NOW()
        ),
        (
          'memory_stats',
          'Get a count of your memories grouped by category and status. Use this to understand your knowledge inventory and decide what to prune or update.',
          'memory_stats',
          true,
          true,
          '{"properties": {}, "required": []}',
          '{}',
          NOW(),
          NOW()
        )
      ON CONFLICT (name) DO NOTHING;
    SQL

    # Also update memory_search schema to document the new optional parameters
    execute <<~SQL
      UPDATE tools
      SET
        parameters_schema = '{"properties": {"query": {"type": "string", "description": "What to search for in your memories"}, "limit": {"type": "integer", "description": "Max results to return (1-20, default 10)"}, "category": {"type": "string", "description": "Filter by category: user_preference, project_context, decision, learned_behavior, factual, general", "enum": ["user_preference", "project_context", "decision", "learned_behavior", "factual", "general"]}, "status": {"type": "string", "description": "Filter by status (default: active)", "enum": ["active", "archived", "superseded"]}}, "required": ["query"]}',
        updated_at = NOW()
      WHERE name = 'memory_search' AND builtin = true;
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM tools
      WHERE name IN ('memory_store', 'memory_update', 'memory_stats')
        AND builtin = true;
    SQL

    # Restore original memory_search schema
    execute <<~SQL
      UPDATE tools
      SET
        parameters_schema = '{"properties": {"query": {"type": "string", "description": "What to search for in your memories"}, "limit": {"type": "integer", "description": "Max results to return (1-20, default 10)"}}, "required": ["query"]}',
        updated_at = NOW()
      WHERE name = 'memory_search' AND builtin = true;
    SQL
  end
end
