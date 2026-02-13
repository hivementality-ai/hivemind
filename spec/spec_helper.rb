# frozen_string_literal: true

RSpec.configure do |config|
  # Expectations configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mocks configuration
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Shared context metadata behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Focus filtering - allows running specific tests with :focus tag
  config.filter_run_when_matching :focus

  # Persist example status for --only-failures and --next-failure
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Disable monkey patching
  config.disable_monkey_patching!

  # Verbose output when running single files
  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  # Profile slowest examples
  config.profile_examples = 10

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed randomization for reproducible test failures
  Kernel.srand config.seed

  # Show warnings
  config.warnings = false
end
