FactoryBot.define do
  factory :channel do
    sequence(:name) { |n| "Channel #{n}" }
    channel_type { "telegram" }
    config { {} }
    enabled { true }

    trait :telegram do
      channel_type { "telegram" }
      name { "Telegram Bot" }
      config { { bot_token: "123456:ABC-DEF", chat_id: "123456789" } }
    end

    trait :discord do
      channel_type { "discord" }
      name { "Discord Bot" }
      config { { bot_token: "discord_token_123", guild_id: "123456789" } }
    end

    trait :slack do
      channel_type { "slack" }
      name { "Slack Bot" }
      config { { bot_token: "xoxb-123", channel_id: "C123456" } }
    end

    trait :whatsapp do
      channel_type { "whatsapp" }
      name { "WhatsApp" }
      config { { connector_url: "http://connector:3002" } }
    end

    trait :signal do
      channel_type { "signal" }
      name { "Signal" }
      config { { "api_url" => "http://signal-cli:8080", "phone_number" => "+12175551234" } }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
