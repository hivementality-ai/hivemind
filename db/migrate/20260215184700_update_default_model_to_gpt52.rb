# frozen_string_literal: true

class UpdateDefaultModelToGpt52 < ActiveRecord::Migration[8.1]
  def change
    change_column_default :agents, :llm_model, "gpt-5.2"
  end
end
