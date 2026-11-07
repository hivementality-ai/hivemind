# frozen_string_literal: true

class CreateSavedPages < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_pages do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.references :agent, foreign_key: { on_delete: :nullify }
      t.references :session, foreign_key: { on_delete: :nullify }
      t.references :research_session, index: false, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :source_kind, null: false, default: "chat"

      t.timestamps
    end

    add_index :saved_pages, :created_at
    add_index :saved_pages, :research_session_id, unique: true, where: "research_session_id IS NOT NULL", name: "index_saved_pages_on_unique_research_session"
  end
end
