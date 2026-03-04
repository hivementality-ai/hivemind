# frozen_string_literal: true

class AddEgressPolicyToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :egress_policy, :jsonb, default: {}, null: false
  end
end
