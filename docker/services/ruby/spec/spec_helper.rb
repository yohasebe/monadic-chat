# frozen_string_literal: true

require 'rspec'
require 'rspec/retry'
require 'bundler/setup'

# Load the application
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Basic RSpec configuration without mocks
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = false

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Configure rspec-retry for E2E tests
  config.verbose_retry = true # Show retry status
  config.display_try_failure_messages = true # Show why test failed before retry
  
  # Only retry E2E tests, not unit tests
  config.around :each, type: :e2e do |example|
    example.run_with_retry retry: 3, retry_wait: 10, exceptions_to_retry: [
      RuntimeError, # For timeout errors
      Net::ReadTimeout,
      Net::OpenTimeout,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      JSON::ParserError, # For WebSocket response parsing issues
      RSpec::Expectations::ExpectationNotMetError # For transient test failures
    ]
  end
end

# Minimal constants needed for tests
unless defined?(CONFIG)
  CONFIG = {}
end

unless defined?(IN_CONTAINER)
  IN_CONTAINER = false
end