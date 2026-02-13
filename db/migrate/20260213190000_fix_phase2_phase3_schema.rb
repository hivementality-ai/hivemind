class FixPhase2Phase3Schema < ActiveRecord::Migration[8.1]
  def change
    # Make team_id nullable on agents (model says optional: true)
    change_column_null :agents, :team_id, true

    # Add missing columns from Phase 2/3 builds
    unless column_exists?(:device_pairings, :device_name)
      add_column :device_pairings, :device_name, :string
    end

    unless column_exists?(:scheduled_tasks, :last_error_at)
      add_column :scheduled_tasks, :last_error_at, :string
    end
  end
end
