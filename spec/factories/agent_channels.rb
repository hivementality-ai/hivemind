FactoryBot.define do
  factory :agent_channel do
    association :agent
    association :channel
    vault_token_key { "slack_agent_#{agent&.id}_bot_token" }
    external_bot_user_id { nil }
    is_default { false }
    config { {} }
    
    trait :with_bot_token do
      vault_token_key { "test_token_key" }
      
      after(:create) do |agent_channel|
        # Mock the VaultEntry for testing
        allow(VaultEntry).to receive(:find_by)
          .with(namespace: "channel_credentials", key: agent_channel.vault_token_key)
          .and_return(double(value: "xoxb-test-token"))
      end
    end
    
    trait :default do
      is_default { true }
    end
    
    trait :with_bot_user_id do
      external_bot_user_id { "U123456789" }
    end
  end
end