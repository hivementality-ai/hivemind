# frozen_string_literal: true

# Start SimpleCov before anything else (skip for system tests)
unless ENV['DISABLE_SIMPLECOV']
  require 'simplecov'
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter
  ])
  SimpleCov.start 'rails' do
    add_filter '/spec/'
    add_filter '/config/'
    add_filter '/vendor/'
    add_filter '/app/channels/'
    add_filter '/app/mailers/'
    add_filter '/app/helpers/'

    # Coverage thresholds — raise as coverage improves
    minimum_coverage 30
    minimum_coverage_by_file 0

    # Track branch coverage
    enable_coverage :branch
    minimum_coverage branch: 10
  end
end

require 'spec_helper'
ENV['RAILS_ENV'] = 'test'
require_relative '../config/environment'

abort("FATAL: Refusing to run specs in #{Rails.env} mode! Tests MUST run in the test environment.") unless Rails.env.test?

require 'rspec/rails'
require 'shoulda/matchers'
require 'webmock/rspec'

# Allow localhost connections for Capybara system specs (browser <-> server)
WebMock.disable_net_connect!(allow_localhost: true)
require 'factory_bot_rails'

# Load support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # FactoryBot syntax methods
  config.include FactoryBot::Syntax::Methods

  # Devise test helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system

  # Remove fixture path since we're using factories
  config.fixture_paths = []

  # DatabaseCleaner will handle transaction management
  config.use_transactional_fixtures = false

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter Rails gems from backtraces
  config.filter_rails_from_backtrace!

  # DatabaseCleaner configuration
  config.before(:suite) do
    DatabaseCleaner.allow_remote_database_url = true
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  # System specs use a separate browser thread — must use truncation
  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  end

  # Sidekiq test mode
  config.before do
    require 'sidekiq/testing'
    Sidekiq::Testing.fake!
  end

  config.after do
    Sidekiq::Job.clear_all
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
