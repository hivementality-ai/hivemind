# frozen_string_literal: true

FactoryBot.define do
  factory :agent_connector_exclusion do
    agent
    connector
  end
end
