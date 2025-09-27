# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require_relative 'file_operations'

module AutoForge
  module Utils
    module DirectoryOperations
      extend self
      include FileOperations

      class DirectoryOperationError < StandardError; end

      # Create directory structure from nested hash
      # @param base_path [String] Base directory path
      # @param structure [Hash] Nested hash representing directory structure
      # @param options [Hash] Options including :with_files for file creation
      # @return [Hash] Result with created paths
      #
      # Example structure:
      # {
      #   "src" => {
      #     "components" => {
      #       "Header.js" => "// Header component"
      #     },
      #     "utils" => {
      #       "helpers.js" => "// Helper functions"
      #     }
      #   },
      #   "tests" => {}
      # }
      def create_directory_structure(base_path, structure, options = {})
        created_dirs = []
        created_files = []

        begin
          process_structure(base_path, structure, created_dirs, created_files)

          {
            success: true,
            base_path: base_path,
            directories: created_dirs,
            files: created_files,
            stats: {
              dir_count: created_dirs.length,
              file_count: created_files.length
            }
          }
        rescue => e
          raise DirectoryOperationError, "Failed to create structure: #{e.message}"
        end
      end

      # Get directory tree structure
      # @param path [String] Root directory path
      # @param options [Hash] Options including :max_depth, :include_files, :exclude_patterns
      # @return [Hash] Tree structure
      def get_directory_tree(path, options = {})
        unless File.directory?(path)
          raise DirectoryOperationError, "Not a directory: #{path}"
        end

        max_depth = options[:max_depth] || 10
        include_files = options.fetch(:include_files, true)
        exclude_patterns = options[:exclude_patterns] || [/\.git/, /node_modules/, /\.DS_Store/]

        build_tree(path, 0, max_depth, include_files, exclude_patterns)
      end

      # Batch generate multiple files atomically
      # @param base_path [String] Base directory for file generation
      # @param file_specs [Array<Hash>] Array of file specifications
      # @param options [Hash] Options including :atomic, :create_dirs
      # @return [Hash] Result with success status and created files
      #
      # Example file_specs:
      # [
      #   { path: "src/index.js", content: "console.log('Hello');" },
      #   { path: "src/style.css", content: "body { margin: 0; }" }
      # ]
      def batch_generate_files(base_path, file_specs, options = {})
        atomic = options.fetch(:atomic, true)
        create_dirs = options.fetch(:create_dirs, true)

        results = []
        created_files = []

        begin
          file_specs.each do |spec|
            relative_path = spec[:path] || spec["path"]
            content = spec[:content] || spec["content"] || ""

            raise DirectoryOperationError, "Missing path in file spec" unless relative_path

            full_path = File.join(base_path, relative_path)

            # Create directory if needed
            if create_dirs
              dir = File.dirname(full_path)
              FileUtils.mkdir_p(dir) unless File.directory?(dir)
            end

            # Write file with verification
            result = write_file_with_verification(full_path, content, options)

            if result[:success]
              created_files << full_path
              results << {
                path: relative_path,
                full_path: full_path,
                size: result[:size],
                success: true
              }
            else
              raise DirectoryOperationError, "Failed to create #{relative_path}" if atomic
              results << {
                path: relative_path,
                success: false,
                error: "Write failed"
              }
            end
          end

          {
            success: true,
            base_path: base_path,
            files: results,
            total_files: created_files.length,
            total_size: created_files.sum { |f| File.size(f) rescue 0 }
          }

        rescue => e
          # Rollback if atomic operation failed
          if atomic
            created_files.each { |f| File.delete(f) rescue nil }
            raise DirectoryOperationError, "Batch generation failed (rolled back): #{e.message}"
          end

          {
            success: false,
            error: e.message,
            partial_results: results
          }
        end
      end

      # Format directory tree for display
      # @param path [String] Directory path
      # @param options [Hash] Display options
      # @return [String] Formatted tree string
      def format_tree_display(path, options = {})
        tree = get_directory_tree(path, options)
        lines = []
        format_tree_recursive(tree, "", lines, true)
        lines.join("\n")
      end

      private

      def process_structure(base_path, structure, created_dirs, created_files, current_path = "")
        structure.each do |name, value|
          path = current_path.empty? ? name : File.join(current_path, name)
          full_path = File.join(base_path, path)

          if value.is_a?(Hash)
            # It's a directory with possible subdirectories/files
            unless File.directory?(full_path)
              FileUtils.mkdir_p(full_path)
              created_dirs << full_path
            end

            # Recursively process subdirectories
            process_structure(base_path, value, created_dirs, created_files, path)
          else
            # It's a file with content
            dir = File.dirname(full_path)
            unless File.directory?(dir)
              FileUtils.mkdir_p(dir)
              created_dirs << dir unless created_dirs.include?(dir)
            end

            write_file_with_verification(full_path, value.to_s)
            created_files << full_path
          end
        end
      end

      def build_tree(path, current_depth, max_depth, include_files, exclude_patterns)
        return nil if current_depth > max_depth

        base_name = File.basename(path)

        # Check exclusions
        exclude_patterns.each do |pattern|
          return nil if base_name.match?(pattern)
        end

        if File.directory?(path)
          children = {}

          Dir.foreach(path) do |entry|
            next if entry == "." || entry == ".."

            child_path = File.join(path, entry)
            child_tree = build_tree(child_path, current_depth + 1, max_depth, include_files, exclude_patterns)

            children[entry] = child_tree unless child_tree.nil?
          end

          {
            type: "directory",
            name: base_name,
            path: path,
            children: children
          }
        elsif include_files
          {
            type: "file",
            name: base_name,
            path: path,
            size: (File.size(path) rescue 0)
          }
        else
          nil
        end
      end

      def format_tree_recursive(node, prefix, lines, is_last)
        return unless node

        # Connector symbols
        connector = is_last ? "└── " : "├── "

        # Add current node
        if node[:type] == "directory"
          lines << "#{prefix}#{connector}📁 #{node[:name]}/"

          # Process children
          children = node[:children] || {}
          children_array = children.to_a

          children_array.each_with_index do |(name, child), index|
            is_child_last = (index == children_array.length - 1)
            child_prefix = prefix + (is_last ? "    " : "│   ")
            format_tree_recursive(child, child_prefix, lines, is_child_last)
          end
        else
          size_str = node[:size] ? " (#{node[:size]} bytes)" : ""
          lines << "#{prefix}#{connector}📄 #{node[:name]}#{size_str}"
        end
      end
    end
  end
end

# Inline tests
if __FILE__ == $0
  require 'minitest/autorun'
  require 'tmpdir'

  class DirectoryOperationsTest < Minitest::Test
    include AutoForge::Utils::DirectoryOperations

    def setup
      @test_dir = Dir.mktmpdir("autoforge_dir_test")
    end

    def teardown
      FileUtils.rm_rf(@test_dir) if @test_dir && File.directory?(@test_dir)
    end

    def test_create_directory_structure
      structure = {
        "src" => {
          "components" => {
            "App.js" => "// App component"
          },
          "utils" => {},
          "index.js" => "// Entry point"
        },
        "tests" => {
          "app.test.js" => "// Tests"
        }
      }

      result = create_directory_structure(@test_dir, structure)

      assert result[:success]
      assert File.directory?(File.join(@test_dir, "src"))
      assert File.directory?(File.join(@test_dir, "src", "components"))
      assert File.directory?(File.join(@test_dir, "src", "utils"))
      assert File.directory?(File.join(@test_dir, "tests"))

      assert File.exist?(File.join(@test_dir, "src", "components", "App.js"))
      assert File.exist?(File.join(@test_dir, "src", "index.js"))
      assert File.exist?(File.join(@test_dir, "tests", "app.test.js"))

      app_content = File.read(File.join(@test_dir, "src", "components", "App.js"))
      assert_equal "// App component", app_content
    end

    def test_get_directory_tree
      # Create test structure
      FileUtils.mkdir_p(File.join(@test_dir, "dir1", "subdir"))
      FileUtils.mkdir_p(File.join(@test_dir, "dir2"))
      File.write(File.join(@test_dir, "file1.txt"), "content1")
      File.write(File.join(@test_dir, "dir1", "file2.txt"), "content2")

      tree = get_directory_tree(@test_dir)

      assert_equal "directory", tree[:type]
      assert tree[:children].key?("dir1")
      assert tree[:children].key?("dir2")
      assert tree[:children].key?("file1.txt")

      dir1 = tree[:children]["dir1"]
      assert_equal "directory", dir1[:type]
      assert dir1[:children].key?("subdir")
      assert dir1[:children].key?("file2.txt")
    end

    def test_batch_generate_files
      file_specs = [
        { path: "app/main.js", content: "console.log('main');" },
        { path: "app/style.css", content: "body { margin: 0; }" },
        { path: "config.json", content: '{"name": "test"}' }
      ]

      result = batch_generate_files(@test_dir, file_specs)

      assert result[:success]
      assert_equal 3, result[:total_files]

      assert File.exist?(File.join(@test_dir, "app", "main.js"))
      assert File.exist?(File.join(@test_dir, "app", "style.css"))
      assert File.exist?(File.join(@test_dir, "config.json"))

      main_content = File.read(File.join(@test_dir, "app", "main.js"))
      assert_equal "console.log('main');", main_content
    end

    def test_batch_generate_files_atomic_rollback
      file_specs = [
        { path: "file1.txt", content: "content1" },
        { path: nil, content: "This will fail" }  # Invalid spec
      ]

      assert_raises(AutoForge::Utils::DirectoryOperations::DirectoryOperationError) do
        batch_generate_files(@test_dir, file_specs, atomic: true)
      end

      # First file should be rolled back
      refute File.exist?(File.join(@test_dir, "file1.txt"))
    end

    def test_format_tree_display
      structure = {
        "project" => {
          "src" => {
            "main.js" => "// main"
          },
          "README.md" => "# Project"
        }
      }

      create_directory_structure(@test_dir, structure)
      tree_display = format_tree_display(@test_dir)

      assert tree_display.include?("📁")
      assert tree_display.include?("📄")
      assert tree_display.include?("main.js")
      assert tree_display.include?("README.md")
    end
  end

  puts "\n=== Running DirectoryOperations Tests ==="
end