# frozen_string_literal: true

class UpdateDefaultModelToGpt54 < ActiveRecord::Migration[8.1]
  def up
    change_column_default :agents, :llm_model, "gpt-5.4"
  end

  def down
    change_column_default :agents, :llm_model, "gpt-5.2"
  end
end
