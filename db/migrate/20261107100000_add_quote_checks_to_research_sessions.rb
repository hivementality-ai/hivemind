# frozen_string_literal: true

# Per-quote verification results for a research report: passage, source and verified status.
class AddQuoteChecksToResearchSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :research_sessions, :quote_checks, :jsonb, default: {}, null: false
  end
end
