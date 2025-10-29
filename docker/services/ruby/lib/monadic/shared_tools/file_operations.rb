# frozen_string_literal: true

# Shared file operations tools for Monadic Chat applications
# Provides unified file operations across all apps with Unicode support
#
# This module integrates the best features from Chat Plus and Coding Assistant:
# - Unicode filename support (from Chat Plus)
# - Structured Hash responses (from Coding Assistant)
# - Automatic directory creation (from Coding Assistant)
# - Comprehensive error handling (from both)
# - Filepath-based interface for maximum flexibility

module MonadicSharedTools
  module FileOperations
    include MonadicHelper

    # Read a file from the shared folder
    #
    # @param filepath [String] Relative or absolute path to the file
    # @return [Hash] Result hash with success status and file data
    # @example
    #   read_file_from_shared_folder(filepath: "reports/summary.md")
    #   => {
    #        success: true,
    #        filepath: "reports/summary.md",
    #        content: "# Summary\n...",
    #        metadata: {
    #          size: 1234,
    #          modified_at: "2025-10-29T10:00:00Z",
    #          lines: 42
    #        }
    #      }
    def read_file_from_shared_folder(filepath:)
      data_dir = Monadic::Utils::Environment.data_path

      # Handle both absolute and relative paths
      full_path = if filepath.start_with?('/')
                    filepath
                  else
                    File.join(data_dir, filepath)
                  end

      # Security: Validate path is within shared folder
      unless validate_file_path(full_path)
        return {
          success: false,
          error: "File path is outside the shared folder or invalid",
          filepath: filepath
        }
      end

      # Check if file exists
      unless File.exist?(full_path)
        return {
          success: false,
          error: "File not found",
          filepath: filepath
        }
      end

      # Check if it's a file (not a directory)
      unless File.file?(full_path)
        return {
          success: false,
          error: "Path is a directory, not a file",
          filepath: filepath
        }
      end

      # Read file content
      begin
        content = File.read(full_path, encoding: "UTF-8")

        {
          success: true,
          filepath: filepath,
          content: content,
          metadata: {
            size: File.size(full_path),
            modified_at: File.mtime(full_path).iso8601,
            created_at: File.ctime(full_path).iso8601,
            lines: content.lines.count
          }
        }
      rescue Errno::EACCES => e
        {
          success: false,
          error: "Permission denied",
          filepath: filepath
        }
      rescue StandardError => e
        {
          success: false,
          error: "Error reading file: #{e.message}",
          filepath: filepath
        }
      end
    end

    # Write or append content to a file in the shared folder
    #
    # @param filepath [String] Path to the file (relative to shared folder or absolute)
    #                          Supports subdirectories and Unicode characters
    # @param content [String] Content to write
    # @param mode [String] Write mode: "write" (overwrite) or "append" (default: "write")
    # @return [Hash] Result hash with success status and file info
    # @example
    #   write_file_to_shared_folder(
    #     filepath: "プロジェクト/2025年/日本語レポート.md",
    #     content: "# 内容\n",
    #     mode: "write"
    #   )
    #   => {
    #        success: true,
    #        filepath: "プロジェクト/2025年/日本語レポート.md",
    #        full_path: "/Users/yohasebe/monadic/data/プロジェクト/2025年/日本語レポート.md",
    #        action: "created",
    #        metadata: { size: 15, bytes_added: 15 }
    #      }
    def write_file_to_shared_folder(filepath:, content:, mode: "write")
      # Validate mode parameter
      unless ["write", "append"].include?(mode)
        return {
          success: false,
          error: "Invalid mode. Use 'write' to overwrite or 'append' to add to existing file"
        }
      end

      data_dir = Monadic::Utils::Environment.data_path

      # Handle both absolute and relative paths
      if filepath.start_with?('/')
        full_path = filepath
        relative_path = filepath.sub(/^#{Regexp.escape(data_dir)}\//, '')
      else
        # Sanitize path while preserving Unicode characters and directory structure
        # Split path into parts, sanitize each part individually
        parts = filepath.split('/')
        safe_parts = parts.map do |part|
          # Preserve Unicode (Japanese, Chinese, Korean, etc.)
          # Remove only dangerous filesystem characters: \ : * ? " < > |
          # Forward slash is handled by split/join
          part.gsub(/[\\:\*\?\"\<\>\|]/, '_')
        end

        safe_filepath = safe_parts.join('/')
        full_path = File.join(data_dir, safe_filepath)
        relative_path = safe_filepath
      end

      # Security: Validate path is within shared folder
      unless validate_file_path(full_path)
        return {
          success: false,
          error: "File path is outside the shared folder or invalid",
          filepath: filepath
        }
      end

      begin
        # Automatically create parent directories
        dir = File.dirname(full_path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        # Check if file exists (for action reporting)
        file_existed = File.exist?(full_path)
        original_size = file_existed ? File.size(full_path) : 0

        # Determine file mode ('w' = write/overwrite, 'a' = append)
        file_mode = mode == "append" ? 'a' : 'w'

        # Write the file with UTF-8 encoding
        File.open(full_path, file_mode, encoding: "UTF-8") do |f|
          f.write(content)
        end

        # Verify the file was written
        unless File.exist?(full_path)
          return {
            success: false,
            error: "File could not be verified after writing",
            filepath: relative_path
          }
        end

        # Determine action performed
        action = if mode == "append" && file_existed
                   "appended"
                 elsif file_existed
                   "overwritten"
                 else
                   "created"
                 end

        # Calculate new file size
        file_size = File.size(full_path)

        {
          success: true,
          filepath: relative_path,
          full_path: full_path,
          action: action,
          metadata: {
            size: file_size,
            bytes_added: mode == "append" ? file_size - original_size : file_size,
            original_size: file_existed ? original_size : nil
          }
        }

      rescue Errno::ENOSPC => e
        {
          success: false,
          error: "Not enough disk space",
          filepath: relative_path
        }
      rescue Errno::EACCES => e
        {
          success: false,
          error: "Permission denied",
          filepath: relative_path
        }
      rescue StandardError => e
        {
          success: false,
          error: "Error writing file: #{e.message}",
          filepath: relative_path
        }
      end
    end

    # List all files and directories in the shared folder
    #
    # @param directory [String, nil] Subdirectory to list (optional, defaults to root)
    # @return [Hash] Result hash with success status and file/directory listings
    # @example
    #   list_files_in_shared_folder(directory: "reports")
    #   => {
    #        success: true,
    #        path: "/reports",
    #        directories: [
    #          {name: "2025", type: "directory", items: 3},
    #          {name: "archive", type: "directory", items: 10}
    #        ],
    #        files: [
    #          {name: "summary.md", type: "file", size: 1234, modified_at: "...", extension: ".md"},
    #          {name: "data.csv", type: "file", size: 5678, modified_at: "...", extension: ".csv"}
    #        ],
    #        total_directories: 2,
    #        total_files: 2
    #      }
    def list_files_in_shared_folder(directory: nil)
      data_dir = Monadic::Utils::Environment.data_path

      # Determine target directory
      if directory.nil? || directory.empty?
        target_dir = data_dir
        relative_path = "/"
      else
        # Remove leading slash if present
        directory = directory.sub(/^\//, '')
        target_dir = File.join(data_dir, directory)
        relative_path = "/#{directory}"

        # Security: Validate path is within shared folder
        unless validate_file_path(target_dir)
          return {
            success: false,
            error: "Directory path is outside the shared folder or invalid",
            path: relative_path
          }
        end
      end

      # Check if directory exists
      unless File.exist?(target_dir)
        return {
          success: false,
          error: "Directory not found",
          path: relative_path
        }
      end

      # Check if it's actually a directory
      unless File.directory?(target_dir)
        return {
          success: false,
          error: "Path is not a directory",
          path: relative_path
        }
      end

      begin
        # Get entries, excluding hidden files (starting with '.')
        entries = Dir.entries(target_dir).reject { |e| e.start_with?('.') }

        directories = []
        files = []

        # Process each entry
        entries.sort.each do |entry|
          full_entry_path = File.join(target_dir, entry)

          if File.directory?(full_entry_path)
            # Count items in subdirectory
            item_count = Dir.entries(full_entry_path).reject { |e| e.start_with?('.') }.size

            directories << {
              name: entry,
              type: "directory",
              items: item_count
            }
          else
            # Get file metadata
            files << {
              name: entry,
              type: "file",
              size: File.size(full_entry_path),
              modified_at: File.mtime(full_entry_path).iso8601,
              extension: File.extname(entry)
            }
          end
        end

        {
          success: true,
          path: relative_path,
          directories: directories,
          files: files,
          total_directories: directories.size,
          total_files: files.size,
          total_items: entries.size
        }

      rescue Errno::EACCES => e
        {
          success: false,
          error: "Permission denied accessing directory",
          path: relative_path
        }
      rescue StandardError => e
        {
          success: false,
          error: "Error listing files: #{e.message}",
          path: relative_path
        }
      end
    end
  end
end
