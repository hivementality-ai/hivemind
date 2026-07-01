# frozen_string_literal: true

class AddFtsToSessions < ActiveRecord::Migration[8.1]
  def up
    # Add tsvector column to hold pre-computed FTS document for each session.
    # We combine: title (weight A), conversation_summary (weight B),
    # and all transcript message content strings (weight C).
    add_column :sessions, :fts_vector, :tsvector

    # GIN index for fast full-text lookups
    add_index :sessions, :fts_vector, using: :gin, name: "index_sessions_on_fts_vector"

    # Backfill existing rows
    execute <<~SQL
      UPDATE sessions
      SET fts_vector = (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(conversation_summary, '')), 'B') ||
        setweight(
          to_tsvector(
            'english',
            coalesce(
              (
                SELECT string_agg(msg->>'content', ' ')
                FROM jsonb_array_elements(
                  CASE jsonb_typeof(transcript) WHEN 'array' THEN transcript ELSE '[]'::jsonb END
                ) AS msg
                WHERE jsonb_typeof(msg->'content') = 'string'
              ),
              ''
            )
          ),
          'C'
        )
      )
    SQL

    # Trigger function — rebuilds fts_vector on INSERT or UPDATE of relevant columns
    execute <<~SQL
      CREATE OR REPLACE FUNCTION sessions_fts_update() RETURNS trigger AS $$
      BEGIN
        NEW.fts_vector :=
          setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(NEW.conversation_summary, '')), 'B') ||
          setweight(
            to_tsvector(
              'english',
              coalesce(
                (
                  SELECT string_agg(msg->>'content', ' ')
                  FROM jsonb_array_elements(
                    CASE jsonb_typeof(NEW.transcript) WHEN 'array' THEN NEW.transcript ELSE '[]'::jsonb END
                  ) AS msg
                  WHERE jsonb_typeof(msg->'content') = 'string'
                ),
                ''
              )
            ),
            'C'
          );
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER sessions_fts_trigger
      BEFORE INSERT OR UPDATE OF title, conversation_summary, transcript
      ON sessions
      FOR EACH ROW
      EXECUTE FUNCTION sessions_fts_update();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS sessions_fts_trigger ON sessions;"
    execute "DROP FUNCTION IF EXISTS sessions_fts_update();"
    remove_index :sessions, name: "index_sessions_on_fts_vector"
    remove_column :sessions, :fts_vector
  end
end
