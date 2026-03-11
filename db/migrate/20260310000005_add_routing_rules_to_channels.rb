# frozen_string_literal: true

class AddRoutingRulesToChannels < ActiveRecord::Migration[8.0]
  def change
    add_column :channels, :routing_rules, :jsonb, default: [], null: false
  end
end
