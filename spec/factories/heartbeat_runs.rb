# frozen_string_literal: true

FactoryBot.define do
  factory :heartbeat_run do
    session
    agent { session.agent }
    status { :healthy }
    checks { {} }
    checked_at { Time.current }
  end
end
