class AddCustomSoulToTeams < ActiveRecord::Migration[8.0]
  def change
    add_column :teams, :custom_soul, :text
  end
end
