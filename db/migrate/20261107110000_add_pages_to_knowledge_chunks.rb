# frozen_string_literal: true

class AddPagesToKnowledgeChunks < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_chunks, :page_start, :integer
    add_column :knowledge_chunks, :page_end, :integer
  end
end
