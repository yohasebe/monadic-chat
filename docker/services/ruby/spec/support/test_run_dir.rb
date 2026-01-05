# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module Monadic
  # Manages test run directories and artifacts
  module TestRunDir
    class << self
      # Get project root directory (repository root, not Ruby service directory)
      def project_root
        @project_root ||= begin
          # Start from current file location
          current_dir = __dir__

          # Look for repository root markers (package.json, .git directory)
          while current_dir != '/'
            if File.exist?(File.join(current_dir, 'package.json')) &&
               File.directory?(File.join(current_dir, '.git'))
              return current_dir
            end
            current_dir = File.dirname(current_dir)
          end

          # Fallback: assume we're in docker/services/ruby/spec/support
          # Go up to repository root: ../../../../..
          File.expand_path('../../../../..', __dir__)
        end
      end

      # Get or create the current test run directory
      # If TEST_OUTPUT_DIR is set, use it (for unified test:all runs)
      def current_run_dir
        @current_run_dir ||= begin
          if ENV['TEST_OUTPUT_DIR'] && !ENV['TEST_OUTPUT_DIR'].empty?
            dir = ENV['TEST_OUTPUT_DIR']
            FileUtils.mkdir_p(dir)
            dir
          else
            timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
            dir = File.join(project_root, 'tmp', 'test_results', timestamp)
            FileUtils.mkdir_p(dir)
            dir
          end
        end
      end

      # Reset cached directory (needed when TEST_OUTPUT_DIR changes between runs)
      def reset!
        @current_run_dir = nil
      end

      # Get path to a file in the current test run directory
      def path(filename)
        File.join(current_run_dir, filename)
      end

      # Write environment metadata
      def write_env_meta
        meta = {
          ruby_version: RUBY_VERSION,
          rspec_version: RSpec::Core::Version::STRING,
          timestamp: Time.now.utc.iso8601,
          env: {
            providers: ENV['PROVIDERS'],
            run_api: ENV['RUN_API'],
            run_media: ENV['RUN_MEDIA'],
            include_ollama: ENV['INCLUDE_OLLAMA'],
            gemini_reasoning: ENV['GEMINI_REASONING'],
            api_max_tokens: ENV['API_MAX_TOKENS'],
            gemini_max_tokens: ENV['GEMINI_MAX_TOKENS']
          }.compact,
          git: git_meta
        }

        File.write(path('env_meta.json'), JSON.pretty_generate(meta))
      rescue => e
        warn "[TestRunDir] Failed to write env_meta.json: #{e.message}"
      end

      # Get Git metadata
      def git_meta
        {
          branch: git_branch,
          commit: git_commit,
          status: git_status
        }
      rescue => e
        warn "[TestRunDir] Failed to get git metadata: #{e.message}"
        {}
      end

      # Update 'latest' symlink to point to current run
      def update_latest(compact_source: nil)
        latest_link = File.join(project_root, 'tmp', 'test_results', 'latest')

        # Remove old symlink if it exists
        File.unlink(latest_link) if File.symlink?(latest_link) || File.exist?(latest_link)

        # Create new symlink
        File.symlink(File.basename(current_run_dir), latest_link)
      rescue => e
        warn "[TestRunDir] Failed to update latest symlink: #{e.message}"
      end

      private

      def git_branch
        `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      end

      def git_commit
        `git rev-parse --short HEAD 2>/dev/null`.strip
      end

      def git_status
        status = `git status --porcelain 2>/dev/null`.strip
        status.empty? ? 'clean' : 'modified'
      end
    end
  end
end
