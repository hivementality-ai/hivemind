# frozen_string_literal: true

# Marks connectors an agent drafted that wait for a person to approve them.
class AddPendingApprovalToConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :connectors, :pending_approval, :boolean, null: false, default: false
  end
end
