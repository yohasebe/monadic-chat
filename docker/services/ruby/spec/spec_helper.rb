# frozen_string_literal: true

require 'rspec'
require 'bundler/setup'
require 'net/http'
require 'json'

# Load the application
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load configuration for integration tests
require 'dotenv'
CONFIG = {}
config_path = File.expand_path("~/monadic/config/env")
if File.exist?(config_path)
  Dotenv.load(config_path)
  ENV.each { |k, v| CONFIG[k] = v }
end

# Load custom retry mechanism
require_relative 'support/custom_retry'

# Load Docker container manager for automatic container startup
require_relative 'support/docker_container_manager'

# Basic RSpec configuration without mocks
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mock framework is not used - all tests use real implementations
  # See CLAUDE.md for testing philosophy and mock replacement strategies

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
  
  # Automatically start containers for integration and E2E tests
  config.before(:suite) do
    # Only start containers if running integration or E2E tests
    if RSpec.world.filtered_examples.values.flatten.any? { |ex| 
         ex.metadata[:integration] || ex.metadata[:e2e] 
       }
      DockerContainerManager.ensure_containers_running
    end
  end
  
  # Optional: Stop containers after tests (commented out by default)
  # config.after(:suite) do
  #   DockerContainerManager.stop_containers
  # end
end

# Minimal constants needed for tests
unless defined?(CONFIG)
  CONFIG = {}
end

unless defined?(IN_CONTAINER)
  IN_CONTAINER = false
end

# Removed early container startup - handled by before(:suite) hook instead

# Load the unified environment module
require_relative '../lib/monadic/utils/environment'

# Helper module that delegates to the unified Environment module
module PostgreSQLConnectionHelper
  include Monadic::Utils::Environment
  
  # Alias for backward compatibility with existing tests
  def postgres_connection_params(database: 'postgres')
    postgres_params(database: database)
  end
end

# Make the helper available to all specs
RSpec.configure do |config|
  config.include PostgreSQLConnectionHelper
end