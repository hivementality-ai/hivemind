# frozen_string_literal: true

class AddScriptTemplateToTools < ActiveRecord::Migration[8.0]
  def change
    add_column :tools, :script_template, :text
  end
end
