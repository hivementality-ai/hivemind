# frozen_string_literal: true

# Lets a chat session or a project override the agent's provider and model.
# Resolution order is session, then project, then agent. Sessions also gain an
# optional project link so the project level has something to hang off.
class AddBrainOverrideToSessionsAndProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :sessions, :provider_config, null: true, foreign_key: { on_delete: :nullify }
    add_column :sessions, :llm_model, :string
    add_reference :sessions, :project, null: true, foreign_key: { on_delete: :nullify }

    add_reference :projects, :provider_config, null: true, foreign_key: { on_delete: :nullify }
    add_column :projects, :llm_model, :string
  end
end
