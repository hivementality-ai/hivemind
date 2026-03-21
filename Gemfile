source "https://rubygems.org"

ruby "3.4.8"

# Core
gem "rails", "~> 8.1.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

# Frontend
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Auth
gem "devise"
gem "bcrypt", "~> 3.1.7"

# Background Jobs
gem "connection_pool", "~> 2.4"
gem "sidekiq", "~> 8.0"
gem "sidekiq-cron", "~> 2.0"

# WebSocket (ActionCable with Redis)
gem "redis", "~> 5.0"

# Security
gem "rack-attack"

# LLM Providers
gem "ruby-openai", "~> 7.0"
gem "anthropic", "~> 1.25"

# HTTP Client (for webhooks, web fetch, etc.)
gem "faraday", "~> 2.0"
gem "faraday-retry"

# JSON
gem "oj"

# Deployment
gem "kamal", require: false
gem "thruster", require: false

# ActiveRecord Encryption + pgvector for memory search
gem "neighbor", "~> 0.4"

# Image processing
gem "image_processing", "~> 1.2"

# Timezone data
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails"
  gem "faker"
  gem "simplecov", require: false
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

# Discord support
gem "websocket-client-simple", "~> 0.8"
gem "concurrent-ruby", "~> 1.3"
gem "ed25519", "~> 1.3"

group :development do
  gem "web-console"
end

group :test do
  gem "shoulda-matchers"
  gem "webmock"
  gem "database_cleaner-active_record"
  gem "rails-controller-testing"
  gem "capybara"
  gem "selenium-webdriver"
end
