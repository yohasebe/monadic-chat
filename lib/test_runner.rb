# frozen_string_literal: true

require 'yaml'
require 'fileutils'

# Simple test runner for profile-based test execution
class TestRunner
  VALID_SUITES = %w[unit integration system api e2e].freeze
  VALID_API_LEVELS = %w[none standard full].freeze

  def self.show_help
    puts "\n=== Test Profiles ==="
    puts "Usage: rake test:profile[profile_name]"
    puts ""
    
    config = load_config
    if config && config['profiles']
      config['profiles'].each do |name, profile|
        desc = profile['description'] || 'No description'
        suites = profile['suites']&.join(', ') || 'N/A'
        api_level = profile['api_level'] || 'none'
        puts "  #{name.ljust(12)} - #{desc}"
        puts "    #{''.ljust(12)}   Suites: #{suites}, API: #{api_level}"
        puts ""
      end
    else
      puts "  No profiles found. Check config/test/test-config.yml"
    end
    
    puts "\n=== Available Suites ==="
    puts "  unit          - Fast unit tests (no external dependencies)"
    puts "  integration   - Integration tests (may require Docker)"
    puts "  api           - Real API tests (requires API keys)"
    puts "  e2e           - End-to-end tests (full stack)"
    puts ""
    puts "See: docs_dev/test_quickref.md for details"
    puts ""
  end

  def self.load_config
    config_path = ENV['TEST_PROFILE_PATH'] || 'config/test/test-config.yml'
    fallback_path = '.test-config.yml'
    
    path = if File.exist?(config_path)
             config_path
           elsif File.exist?(fallback_path)
             fallback_path
           else
             nil
           end
    
    return nil unless path
    
    YAML.load_file(path)
  rescue => e
    warn "Error loading test config: #{e.message}"
    nil
  end

  attr_reader :suite, :options, :profile

  def initialize(suite_or_profile, options = nil)
    @suite = suite_or_profile
    @options = parse_options(options || '')
    @profile = nil
  end

  def load_profile(profile_name)
    config = self.class.load_config
    return false unless config && config['profiles']
    
    @profile = config['profiles'][profile_name]
    unless @profile
      warn "Profile '#{profile_name}' not found in config"
      return false
    end
    
    true
  end

  def execute
    # Set up test environment
    setup_environment
    
    # Execute tests
    if profile
      execute_profile
    else
      execute_suite
    end
  end

  def execute_profile
    puts "Running test profile: #{@profile['description']}"
    puts ""

    suites = @profile['suites'] || ['unit']
    api_level = @profile['api_level'] || 'none'
    format = @profile['format'] || 'documentation'
    timeout = @profile['timeout'] || 60
    save_logs = @profile['save'] || false

    # Generate unique run_id if saving logs
    @run_id = if save_logs
                "profile_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
              else
                nil
              end

    # Set environment variables based on API level
    set_api_level_env(api_level)

    # Set other environment variables
    ENV['API_TIMEOUT'] = timeout.to_s if timeout

    # Run each suite
    suites.each do |suite|
      puts "\n=== Running #{suite} tests ==="
      run_suite(suite, format, save_logs)
    end

    # Generate HTML report if logs were saved
    if save_logs && @run_id
      puts "\n📄 Generating test reports..."
      generate_reports
    end
  end

  def execute_suite
    suite_name = @suite || 'unit'
    format = @options['format'] || 'documentation'
    save_logs = @options['save'] == 'true'
    @run_id = @options['run_id'] || (save_logs ? "suite_#{Time.now.strftime('%Y%m%d_%H%M%S')}" : nil)

    unless VALID_SUITES.include?(suite_name)
      warn "Invalid suite: #{suite_name}"
      warn "Valid suites: #{VALID_SUITES.join(', ')}"
      return false
    end

    # Set API level if specified
    if @options['api_level']
      set_api_level_env(@options['api_level'])
    end

    run_suite(suite_name, format, save_logs)

    # Generate HTML report if logs were saved
    if save_logs && @run_id
      generate_reports
    end
  end

  private

  def parse_options(options_string)
    opts = {}
    return opts if options_string.nil? || options_string.empty?
    
    options_string.split(',').each do |opt|
      key, value = opt.split('=')
      opts[key.strip] = value&.strip || 'true'
    end
    
    opts
  end

  def setup_environment
    # Load API keys from config if available
    config_path = File.expand_path('~/monadic/config/env')
    if File.exist?(config_path)
      require 'dotenv'
      Dotenv.load(config_path)
    end
    
    # Set PostgreSQL connection for tests
    ENV['POSTGRES_HOST'] ||= 'localhost'
    ENV['POSTGRES_PORT'] ||= '5433'
    ENV['POSTGRES_USER'] ||= 'postgres'
    ENV['POSTGRES_PASSWORD'] ||= 'postgres'
  end

  def set_api_level_env(level)
    case level
    when 'full'
      ENV['RUN_API'] = 'true'
      ENV['RUN_API_E2E'] = 'true'
      ENV['RUN_MEDIA'] = 'true'
    when 'standard'
      ENV['RUN_API'] = 'true'
      ENV['RUN_API_E2E'] = 'true'
      ENV['RUN_MEDIA'] = 'false'
    when 'none'
      ENV['RUN_API'] = 'false'
      ENV['RUN_API_E2E'] = 'false'
      ENV['RUN_MEDIA'] = 'false'
    else
      warn "Unknown API level: #{level}, using 'none'"
      ENV['RUN_API'] = 'false'
      ENV['RUN_API_E2E'] = 'false'
      ENV['RUN_MEDIA'] = 'false'
    end
  end

  def run_suite(suite, format = 'documentation', save_logs = false)
    # Prepare output directory if saving logs
    if save_logs && @run_id
      results_dir = File.expand_path('../../../tmp/test_results', __dir__)
      FileUtils.mkdir_p(results_dir)
      json_file = File.join(results_dir, "#{@run_id}_#{suite}.json")
    end

    Dir.chdir('docker/services/ruby') do
      # Build format options
      format_opts = if save_logs && json_file
                      "--format #{format} --format json --out #{json_file}"
                    else
                      "--format #{format}"
                    end

      case suite
      when 'unit'
        sh_safe "bundle exec rspec spec/unit #{format_opts}"
      when 'integration'
        sh_safe "bundle exec rspec spec/integration #{format_opts}"
      when 'system'
        sh_safe "bundle exec rspec spec/system #{format_opts}"
      when 'api'
        # Run API tests based on RUN_API environment variable
        if ENV['RUN_API'] == 'true'
          sh_safe "bundle exec rspec spec/integration --tag api #{format_opts}"
        else
          puts "Skipping API tests (RUN_API not set)"
        end
      when 'e2e'
        # Use the existing E2E runner script
        sh_safe "./spec/e2e/run_e2e_tests.sh"
      else
        warn "Unknown suite: #{suite}"
        return false
      end
    end

    # Log file location if saved
    if save_logs && json_file && File.exist?(json_file)
      puts "📝 Test results saved to: #{json_file}"
    end

    true
  rescue => e
    warn "Error running #{suite} tests: #{e.message}"
    false
  end

  def sh_safe(command)
    puts "$ #{command}"
    system(command)
    status = $?.exitstatus

    if status != 0
      warn "Command failed with exit code #{status}"
      return false
    end

    true
  end

  def generate_reports
    return unless @run_id

    results_dir = File.expand_path('../../../tmp/test_results', __dir__)

    # Find all JSON files for this run_id
    json_files = Dir.glob(File.join(results_dir, "#{@run_id}_*.json"))

    if json_files.empty?
      warn "No JSON test results found for run_id: #{@run_id}"
      return
    end

    # Generate HTML report for each suite
    json_files.each do |json_file|
      suite_name = File.basename(json_file, '.json').sub(/^#{@run_id}_/, '')
      suite_run_id = "#{@run_id}_#{suite_name}"

      begin
        require_relative '../lib/test_report_html'
        html_file = File.join(results_dir, "report_#{suite_run_id}.html")
        TestReportHTML.generate(results_dir, suite_run_id, html_file)
        puts "  ✓ #{suite_name}: #{html_file}"
      rescue StandardError => e
        warn "  ✗ Failed to generate report for #{suite_name}: #{e.message}"
      end
    end

    # Generate summary report
    puts "\n📊 Test Results Summary:"
    puts "  Run ID: #{@run_id}"
    puts "  Results directory: #{results_dir}"
    puts "  JSON files: #{json_files.length}"
  end
end
