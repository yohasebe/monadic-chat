# frozen_string_literal: true

require 'fileutils'

module AutoForge
  module Utils
    module PathConfig
      extend self

      # Get the base data directory based on environment
      # Uses existing MonadicApp constants when available
      # @return [String] Base data directory path
      def base_data_path
        # Prefer MonadicApp constants (production)
        if defined?(MonadicApp::SHARED_VOL) && defined?(MonadicApp::LOCAL_SHARED_VOL)
          if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
            MonadicApp::SHARED_VOL
          else
            MonadicApp::LOCAL_SHARED_VOL
          end
        # Fallback to Environment module
        elsif defined?(Monadic::Utils::Environment)
          Monadic::Utils::Environment.data_path
        # Last resort for testing
        else
          File.expand_path("~/monadic/data")
        end
      end

      # Get AutoForge specific project directory
      # @return [String] AutoForge project directory path
      def project_base_path
        File.join(base_data_path, "auto_forge")
      end

      # Get backup directory path
      # @return [String] Backup directory path
      def backup_directory_path
        File.join(project_base_path, ".backups")
      end

      # Get templates directory path
      # @return [String] Templates directory path
      def templates_directory_path
        File.join(project_base_path, ".templates")
      end

      # Check if path is within safe boundaries
      # @param path [String] Path to check
      # @return [Boolean] True if path is safe
      def safe_path?(path)
        expanded_path = File.expand_path(path)
        expanded_path.start_with?(base_data_path)
      end

      # Ensure directory exists
      # @param path [String] Directory path
      # @return [String] The path that was ensured
      def ensure_directory(path)
        FileUtils.mkdir_p(path) unless File.directory?(path)
        path
      end

      # Get relative path from base data directory
      # @param full_path [String] Full path
      # @return [String] Relative path
      def relative_from_base(full_path)
        expanded = File.expand_path(full_path)
        base = base_data_path

        if expanded.start_with?(base)
          expanded.sub(base + "/", "")
        else
          full_path
        end
      end

      # Build project path
      # @param project_name [String] Project name
      # @param *parts [Array<String>] Additional path parts
      # @return [String] Full project path
      def build_project_path(project_name, *parts)
        File.join(project_base_path, project_name, *parts)
      end

      # Environment info for debugging
      # @return [Hash] Environment information
      def environment_info
        {
          in_container: defined?(Monadic::Utils::Environment) &&
                       Monadic::Utils::Environment.in_container?,
          base_data_path: base_data_path,
          project_base_path: project_base_path,
          backup_path: backup_directory_path,
          ruby_version: RUBY_VERSION,
          platform: RUBY_PLATFORM
        }
      end
    end
  end
end

# Inline tests
if __FILE__ == $0
  require 'minitest/autorun'

  class PathConfigTest < Minitest::Test
    include AutoForge::Utils::PathConfig

    def test_base_data_path_local
      # Mock local environment
      if defined?(Monadic::Utils::Environment)
        Monadic::Utils::Environment.stub(:in_container?, false) do
          path = base_data_path
          assert path.include?("monadic/data")
          refute path.start_with?("/monadic")
        end
      else
        # When Environment module is not available
        path = base_data_path
        assert path.include?("monadic/data")
      end
    end

    def test_project_base_path
      project_path = project_base_path
      assert project_path.end_with?("auto_forge")
      assert project_path.include?("monadic/data")
    end

    def test_safe_path_check
      safe_path = File.join(base_data_path, "test_file.txt")
      unsafe_path = "/etc/passwd"

      assert safe_path?(safe_path)
      refute safe_path?(unsafe_path)
    end

    def test_relative_from_base
      full_path = File.join(base_data_path, "auto_forge", "project1", "file.txt")
      relative = relative_from_base(full_path)

      assert_equal "auto_forge/project1/file.txt", relative
    end

    def test_build_project_path
      path = build_project_path("my_project", "src", "index.js")

      assert path.include?("auto_forge/my_project/src/index.js")
    end

    def test_environment_info
      info = environment_info

      assert info.key?(:in_container)
      assert info.key?(:base_data_path)
      assert info.key?(:project_base_path)
      assert_equal RUBY_VERSION, info[:ruby_version]
    end
  end

  puts "\n=== Running PathConfig Tests ==="
end