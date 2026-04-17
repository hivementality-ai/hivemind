# frozen_string_literal: true

class AddRawOutputToToolExecutions < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_executions, :raw_output, :text
  end
end
