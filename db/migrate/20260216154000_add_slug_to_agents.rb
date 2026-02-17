# frozen_string_literal: true

class AddSlugToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :slug, :string, null: true

    # Create case-insensitive unique index on slug
    enable_extension "citext" unless extension_enabled?("citext")
    execute "ALTER TABLE agents ALTER COLUMN slug TYPE citext;"
    add_index :agents, :slug, unique: true

    # Generate slugs for existing agents
    reversible do |dir|
      dir.up do
        Agent.reset_column_information
        Agent.find_each do |agent|
          agent.update_column(:slug, agent.name.parameterize(separator: "_"))
        end
      end
    end

    # Make slug NOT NULL after population
    change_column_null :agents, :slug, false
  end
end
