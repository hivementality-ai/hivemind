# frozen_string_literal: true

class AddLibraryFolderToKnowledgeDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_documents, :library_path, :string
    add_column :knowledge_documents, :library_signature, :string
    add_column :knowledge_documents, :removed_at, :datetime
    add_index :knowledge_documents, %i[agent_id library_path],
              unique: true, where: "library_path IS NOT NULL",
              name: "index_knowledge_documents_on_agent_and_library_path"
  end
end
