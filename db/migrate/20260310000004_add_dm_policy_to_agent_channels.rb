# frozen_string_literal: true

class AddDmPolicyToAgentChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_channels, :dm_policy, :jsonb, default: {}, null: false
  end
end
