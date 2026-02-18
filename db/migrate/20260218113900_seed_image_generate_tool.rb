# frozen_string_literal: true

class SeedImageGenerateTool < ActiveRecord::Migration[8.1]
  def up
    # Register image_generate as a builtin tool
    execute <<~SQL
      INSERT INTO tools (name, description, executor_type, builtin, enabled, parameters_schema, config, created_at, updated_at)
      VALUES (
        'image_generate',
        'Generate images from text prompts using DALL-E. Creates images and saves them to the workspace.',
        'image_generate',
        true,
        true,
        '{"properties": {"prompt": {"type": "string", "description": "Text description of the image to generate"}, "size": {"type": "string", "description": "Image size: 1024x1024, 1792x1024, or 1024x1792", "enum": ["1024x1024", "1792x1024", "1024x1792"]}}, "required": ["prompt"]}',
        '{}',
        NOW(),
        NOW()
      )
      ON CONFLICT (name) DO NOTHING;
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM tools WHERE name = 'image_generate' AND builtin = true;
    SQL
  end
end
