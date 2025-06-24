# frozen_string_literal: true

require 'rspec'
require 'bundler/setup'
require 'net/http'
require 'json'

# Load the application
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load custom retry mechanism
require_relative 'support/custom_retry'

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

  # config.profile_examples = 10  # Disabled to avoid unnecessary output
  config.order = :random
  Kernel.srand config.seed

  # Include custom retry helper for E2E tests
  config.include E2ERetryHelper, type: :e2e
end

# Minimal constants needed for tests
unless defined?(CONFIG)
  CONFIG = {}
end

unless defined?(IN_CONTAINER)
  IN_CONTAINER = false
end