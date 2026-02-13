class RenameModelNameToLlmModelOnAgents < ActiveRecord::Migration[8.1]
  def change
    rename_column :agents, :model_name, :llm_model
  end
end
