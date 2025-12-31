# frozen_string_literal: true

require 'rspec'
require 'bundler/setup'
require 'net/http'
require 'json'

# Load the application
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load configuration for integration tests FIRST
require 'dotenv'
CONFIG = {} unless defined?(CONFIG)

# Try multiple config paths
config_paths = [
  File.expand_path("~/monadic/config/env"),
  File.expand_path("../../config/env", __dir__),
  "/monadic/config/env"
]

config_path = config_paths.find { |path| File.exist?(path) }

if config_path
  # Read and parse the config file manually
  File.readlines(config_path).each do |line|
    next if line.strip.empty? || line.strip.start_with?('#')
    key, value = line.strip.split('=', 2)
    next unless key && value
    CONFIG[key] = value
    ENV[key] = value  # Also set in ENV for compatibility
  end
  
  puts "Loaded #{CONFIG.keys.count} config values from #{config_path}" if ENV["DEBUG"]
else
  puts "No config file found at: #{config_paths.join(', ')}" if ENV["DEBUG"]
end

# Initialize global variables used by the application
$MODELS = {} unless defined?($MODELS)
APPS = {} unless defined?(APPS)

# Load core application files AFTER CONFIG is set
require_relative '../lib/monadic/app'
require_relative '../lib/monadic/core'
require_relative '../lib/monadic/utils/selenium_helper'
require_relative '../lib/monadic/dsl'

# Load all vendor helpers for provider matrix tests
require_relative '../lib/monadic/adapters/vendors/openai_helper'
require_relative '../lib/monadic/adapters/vendors/claude_helper'
require_relative '../lib/monadic/adapters/vendors/gemini_helper'
require_relative '../lib/monadic/adapters/vendors/grok_helper'
require_relative '../lib/monadic/adapters/vendors/mistral_helper'
require_relative '../lib/monadic/adapters/vendors/cohere_helper'
require_relative '../lib/monadic/adapters/vendors/perplexity_helper'
require_relative '../lib/monadic/adapters/vendors/deepseek_helper'
require_relative '../lib/monadic/adapters/vendors/ollama_helper'

# App loader module for tests
module TestAppLoader
  @apps_loaded = false

  def self.load_all_apps
    return if @apps_loaded

    app_base_dir = File.expand_path('../apps', __dir__)

    # Collect all app files (rb first, then mdsl)
    app_files = Dir.glob(File.join(app_base_dir, '**/*.{rb,mdsl}')).sort_by do |f|
      [File.extname(f) == '.rb' ? 0 : 1, f]
    end

    loaded_count = 0
    app_files.each do |file|
      basename = File.basename(file)
      next if basename.start_with?('_')  # Skip files starting with underscore
      next if file.include?('/test/')    # Skip test directories

      begin
        MonadicDSL::Loader.load(file)
        loaded_count += 1
      rescue => e
        # Log but continue - some apps may have missing dependencies
        warn "Test loader: Could not load #{basename}: #{e.message}" if ENV['DEBUG']
      end
    end

    # Populate APPS hash by instantiating all MonadicApp subclasses
    # This mimics what init_apps() does in lib/monadic.rb
    populate_apps_hash

    @apps_loaded = true
    puts "TestAppLoader: Loaded #{loaded_count} app files, APPS now has #{APPS.keys.size} entries" if ENV['DEBUG']
  end

  # Populate APPS hash from MonadicApp subclasses (simplified version of init_apps)
  def self.populate_apps_hash
    klass = Object.const_get("MonadicApp")

    klass.subclasses.each do |app_class|
      begin
        app = app_class.new
        class_settings = app_class.instance_variable_get(:@settings) || {}

        # Use ActiveSupport::HashWithIndifferentAccess if available, otherwise regular Hash
        app.settings = if defined?(ActiveSupport::HashWithIndifferentAccess)
                         ActiveSupport::HashWithIndifferentAccess.new(class_settings)
                       else
                         class_settings.transform_keys(&:to_s)
                       end

        app_name = app.settings['app_name'] || app.settings[:app_name]

        # Skip apps with invalid app_name
        next if app_name.nil? || app_name.to_s.strip.empty? || app_name.to_s == "undefined"

        APPS[app_name] = app
        puts "  Registered app: #{app_name}" if ENV['DEBUG']
      rescue => e
        warn "Test loader: Could not instantiate #{app_class.name}: #{e.message}" if ENV['DEBUG']
      end
    end
  end

  def self.loaded?
    @apps_loaded
  end
end

# Load minimal apps by default (for backward compatibility)
unless APPS.any?
  # Load Jupyter Notebook Grok app for basic testing
  mdsl_path = File.expand_path('../apps/jupyter_notebook/jupyter_notebook_grok.mdsl', __dir__)
  if File.exist?(mdsl_path)
    require_relative '../apps/jupyter_notebook/jupyter_notebook_tools'
    load mdsl_path
  end
end

# Load custom retry mechanism
require_relative 'support/custom_retry'

# Load Docker container manager for automatic container startup
require_relative 'support/docker_container_manager'
require_relative 'support/text_response_assertions'

# Load summary formatter (for compact summaries and artifacts)
begin
  require_relative 'support/summary_formatter'
  RSpec.configure do |config|
    # Always add summary formatter to generate artifacts; primary format still controlled by CLI
    config.add_formatter Monadic::SummaryFormatter
  end
rescue LoadError
  # Formatter is optional; tests can still run without it
end

# Basic RSpec configuration without mocks
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mock framework is not used - all tests use real implementations
# Internal testing philosophy and mock strategies are documented in internal maintainer guides.

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

    # Load all apps for matrix tests and artifact tests
    if RSpec.world.filtered_examples.values.flatten.any? { |ex|
         ex.metadata[:matrix] || ex.metadata[:tool_tests] || ex.metadata[:artifacts]
       }
      TestAppLoader.load_all_apps
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
  config.include TextResponseAssertions
end
