# frozen_string_literal: true

class AddConversationSummaryToSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :conversation_summary, :text
    add_column :sessions, :summary_through_index, :integer, default: 0
  end
end
