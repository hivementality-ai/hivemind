# frozen_string_literal: true

class SeedUserModelTools < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO tools (name, description, executor_type, builtin, enabled, parameters_schema, config, created_at, updated_at)
      VALUES
        (
          'user_model',
          'Load your structured user model — a canonical view of all recorded user preferences, grouped by section (Communication Style, Workflow Preferences, Domain Expertise, Recurring Patterns). Call this at the start of a session to understand how the user likes to work.',
          'user_model',
          true,
          true,
          '{"properties": {}, "required": []}',
          '{}',
          NOW(),
          NOW()
        ),
        (
          'user_model_populate',
          'Auto-populate the user model by scanning existing memories and reclassifying entries that look like user preferences. Use this once to bootstrap your user model from memories stored before structured categorization existed. Supports dry_run: true to preview changes.',
          'user_model_populate',
          true,
          true,
          '{"properties": {"dry_run": {"type": "boolean", "description": "Preview what would be reclassified without making changes (default: false)"}}, "required": []}',
          '{}',
          NOW(),
          NOW()
        )
      ON CONFLICT (name) DO NOTHING;
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM tools
      WHERE name IN ('user_model', 'user_model_populate')
        AND builtin = true;
    SQL
  end
end
