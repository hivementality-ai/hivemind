# frozen_string_literal: true

class SeedKnowledgeSearchTool < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      INSERT INTO tools (name, description, executor_type, builtin, enabled, parameters_schema, config, created_at, updated_at)
      VALUES
        (
          'knowledge_search',
          'Search the ingested document knowledge base using semantic similarity. Returns the most relevant text chunks from documents you have ingested. Use this to answer questions grounded in uploaded documents (PDFs, text files).',
          'knowledge_search',
          true,
          true,
          '{"properties": {"query": {"type": "string", "description": "What to look for in the knowledge base"}, "limit": {"type": "integer", "description": "Max chunks to return (1-20, default 5)"}}, "required": ["query"]}',
          '{}',
          NOW(),
          NOW()
        )
      ON CONFLICT (name) DO NOTHING;
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM tools WHERE name = 'knowledge_search' AND builtin = true;
    SQL
  end
end
