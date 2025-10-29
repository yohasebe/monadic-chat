# frozen_string_literal: true

require 'json'
require 'fileutils'

module AutoForge
  class Debugger
    include Monadic::Utils::SeleniumHelper

    def initialize(context = {})
      @context = context || {}
    end

    def debug_html(html_path, options = {})
      start_time = Time.now
      puts "[AutoForgeDebugger] Starting debug at #{start_time.strftime('%Y-%m-%d %H:%M:%S')}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      unless File.exist?(html_path)
        return {
          success: false,
          error: "HTML file not found: #{html_path}"
        }
      end

      # Check if Selenium container is available (with retries)
      if error = check_selenium_or_error
        puts "[AutoForgeDebugger] Selenium not available after retries" if CONFIG && CONFIG["EXTRA_LOGGING"]
        return error
      end

      puts "[AutoForgeDebugger] Selenium available, executing debug" if CONFIG && CONFIG["EXTRA_LOGGING"]

      # Execute the debug script directly
      result = execute_debug_script(html_path, options)

      # Parse and return results
      formatted_result = format_debug_results(result)

      end_time = Time.now
      duration = end_time - start_time
      puts "[AutoForgeDebugger] Debug completed at #{end_time.strftime('%Y-%m-%d %H:%M:%S')}" if CONFIG && CONFIG["EXTRA_LOGGING"]
      puts "[AutoForgeDebugger] Debug duration: #{duration.round(2)} seconds" if CONFIG && CONFIG["EXTRA_LOGGING"]

      # Add timing info to result
      formatted_result[:debug_timing] = {
        start_time: start_time.strftime('%Y-%m-%d %H:%M:%S'),
        end_time: end_time.strftime('%Y-%m-%d %H:%M:%S'),
        duration: duration.round(2)
      }

      formatted_result
    end

    private

    def execute_debug_script(html_path, options = {})
      # Use send_command from MonadicApp (same as visual_web_explorer)
      # This handles Docker execution properly through the established pattern

      # The HTML file is already in ~/monadic/data which is mounted as /monadic/data in containers
      # Convert host path to container path
      shared_volume = ENV['SHARED_VOLUME'] || File.expand_path('~/monadic/data')
      if html_path.start_with?(shared_volume)
        # Path is already in shared volume, just convert to container path
        container_html_path = html_path.sub(shared_volume, '/monadic/data')
      else
        # File is outside shared volume, need to copy it (shouldn't happen with AutoForge)
        temp_html = File.join(shared_volume, "temp_debug_#{Time.now.to_i}.html")
        FileUtils.cp(html_path, temp_html)
        container_html_path = "/monadic/data/#{File.basename(temp_html)}"
      end

      command = "debug_html.py #{container_html_path} --json"

      result = nil
      puts "[AutoForgeDebugger] Executing: #{command}" if CONFIG && CONFIG["EXTRA_LOGGING"]

      # Use send_command if available (when included in MonadicApp)
      if respond_to?(:send_command)
        output = send_command(command: command, container: "python")
      else
        # Fallback to direct docker exec (for standalone use)
        docker_command = "docker exec -w /monadic/data monadic-chat-python-container python /monadic/scripts/utilities/debug_html.py #{container_html_path} --json"
        output = `#{docker_command} 2>&1`
      end

      begin
        result = JSON.parse(output)
      rescue JSON::ParserError => e
        result = {
          'success' => false,
          'errors' => ["Failed to parse debug output: #{e.message}", "Raw output: #{output[0..500]}"]
        }
      end

      # Clean up temporary HTML file (only if we created one)
      if defined?(temp_html) && temp_html && File.exist?(temp_html)
        File.delete(temp_html)
      end

      result
    end

    def format_debug_results(result)
      return { success: false, error: "No debug results" } unless result

      formatted = {
        success: result['success'],
        summary: []
      }

      # Add summary information
      if result['success']
        formatted[:summary] << "✅ Page loaded successfully"
      else
        formatted[:summary] << "❌ Page failed to load"
      end

      # JavaScript errors
      formatted[:javascript_errors] = result['javascript_errors'] || []
      if formatted[:javascript_errors].empty?
        formatted[:summary] << "✅ No JavaScript errors detected"
      else
        formatted[:summary] << "⚠️  Found #{formatted[:javascript_errors].length} JavaScript error(s)"
      end

      # Warnings - will be processed and filtered later
      raw_warnings = result['warnings'] || []

      # Functionality tests
      formatted[:functionality_tests] = result['functionality_tests'] || []
      if formatted[:functionality_tests].any?
        passed = formatted[:functionality_tests].count { |t| t['passed'] }
        total = formatted[:functionality_tests].length
        formatted[:summary] << "🧪 #{passed}/#{total} functionality tests passed"
      end

      # Performance metrics
      if result['performance'] && result['performance']['loadTime']
        load_time = result['performance']['loadTime']
        formatted[:performance] = result['performance']
        status = load_time < 1000 ? "⚡" : load_time < 3000 ? "🔄" : "🐌"
        formatted[:summary] << "#{status} Page load time: #{load_time}ms"
      end

      if result['console_logs'] && !result['console_logs'].empty?
        filtered_logs = result['console_logs'].reject do |log|
          log.to_s.include?("'WebDriver' object has no attribute 'get_log'")
        end
        formatted[:console_logs] = filtered_logs unless filtered_logs.empty?
      end

      # Filter warnings (remove WebDriver log warnings)
      filtered_warnings = raw_warnings.reject do |warning|
        warning.to_s.include?("'WebDriver' object has no attribute 'get_log'")
      end

      formatted[:warnings] = filtered_warnings
      if filtered_warnings.any?
        formatted[:summary] << "⚠️  Found #{filtered_warnings.length} warning(s)"
      elsif raw_warnings.any?
        # Had warnings but all were filtered out
        formatted[:summary] << "✅ No significant warnings"
      end

      formatted[:viewport] = result['viewport'] if result['viewport']

      formatted
    end
  end
end
