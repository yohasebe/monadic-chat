# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'open3'
require 'tempfile'
require_relative 'encoding_helper'
require_relative 'path_config'

module AutoForge
  module Utils
    module FileOperations
      extend self
      include EncodingHelper

      class FileOperationError < StandardError; end
      class VerificationError < FileOperationError; end
      class SafetyError < FileOperationError; end

      # Maximum retries for file operations
      MAX_RETRIES = 3

      # Get backup directory from PathConfig
      def self.backup_dir
        PathConfig.backup_directory_path
      end

      # Write file with verification
      # @param path [String] File path
      # @param content [String] Content to write
      # @param options [Hash] Options including :encoding, :verify_content, :max_retries
      # @return [Hash] Result with :success, :path, :verified, :size
      def write_file_with_verification(path, content, options = {})
        puts "[FileOps] write_file_with_verification called for: #{path}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
        puts "[FileOps] Content length: #{content&.length || 0}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

        encoding = options[:encoding] || 'UTF-8'
        verify_content = options.fetch(:verify_content, true)
        max_retries = options[:max_retries] || MAX_RETRIES

        # Prepare content for writing
        prepared_content = prepare_for_file(content, encoding: encoding)

        # Ensure directory exists
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)
        puts "[FileOps] Directory created/verified: #{dir}" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]

        retries = 0
        last_error = nil

        while retries < max_retries
          begin
            # Write file
            File.write(path, prepared_content, encoding: encoding)

            # Verify file exists
            unless File.exist?(path)
              raise VerificationError, "File not found after write: #{path}"
            end

            # Verify content if requested
            if verify_content
              read_content = File.read(path, encoding: encoding)
              unless read_content == prepared_content
                raise VerificationError, "Content verification failed"
              end
            end

            # Success
            puts "[FileOps] File successfully written and verified: #{path} (#{File.size(path)} bytes)" if defined?(CONFIG) && CONFIG && CONFIG["EXTRA_LOGGING"]
            return {
              success: true,
              path: path,
              verified: true,
              size: File.size(path),
              encoding: encoding
            }

          rescue => e
            last_error = e
            retries += 1
            sleep(0.1 * retries) if retries < max_retries
          end
        end

        # All retries failed
        raise FileOperationError, "Failed after #{max_retries} attempts: #{last_error&.message}"
      end

      # Edit file with backup and rollback capability
      # @param path [String] File path to edit
      # @param options [Hash] Options
      # @yield [String] Block that receives content and returns modified content
      # @return [Hash] Result with :success, :backup_path, :changes
      def edit_file_with_backup(path, options = {}, &block)
        unless File.exist?(path)
          raise FileOperationError, "File does not exist: #{path}"
        end

        unless block_given?
          raise ArgumentError, "Block required for file editing"
        end

        # Create backup
        backup_path = create_backup(path)

        begin
          # Read original content
          original_content = File.read(path)
          original_checksum = Digest::SHA256.hexdigest(original_content)

          # Apply modifications
          modified_content = yield(original_content)

          # Write modified content with verification
          write_file_with_verification(path, modified_content, options)

          # Calculate change metrics
          modified_checksum = Digest::SHA256.hexdigest(modified_content)

          {
            success: true,
            backup_path: backup_path,
            changes: {
              lines_before: original_content.lines.count,
              lines_after: modified_content.lines.count,
              size_before: original_content.bytesize,
              size_after: modified_content.bytesize,
              changed: original_checksum != modified_checksum
            }
          }

        rescue => e
          # Rollback on failure
          restore_from_backup(backup_path, path)
          raise FileOperationError, "Edit failed and rolled back: #{e.message}"
        end
      end

      # Replace content in file
      # @param path [String] File path
      # @param pattern [String, Regexp] Pattern to replace
      # @param replacement [String] Replacement text
      # @param options [Hash] Options
      # @return [Hash] Result with replacement count
      def replace_in_file(path, pattern, replacement, options = {})
        global = options.fetch(:global, true)

        edit_file_with_backup(path, options) do |content|
          if pattern.is_a?(Regexp)
            if global
              content.gsub(pattern, replacement)
            else
              content.sub(pattern, replacement)
            end
          else
            if global
              content.gsub(pattern.to_s, replacement)
            else
              content.sub(pattern.to_s, replacement)
            end
          end
        end
      end

      # Apply patch file safely
      # @param patch_file [String] Path to patch file
      # @param target_dir [String] Directory to apply patch
      # @param options [Hash] Options including :dry_run, :strip
      # @return [Hash] Result with applied files and status
      def apply_patch_safely(patch_file, target_dir, options = {})
        unless File.exist?(patch_file)
          raise FileOperationError, "Patch file not found: #{patch_file}"
        end

        unless File.directory?(target_dir)
          raise FileOperationError, "Target directory not found: #{target_dir}"
        end

        strip_level = options[:strip] || 1
        dry_run = options.fetch(:dry_run, false)

        # Prepare patch command
        cmd = ["patch", "-p#{strip_level}"]
        cmd << "--dry-run" if dry_run
        cmd << "-d"
        cmd << target_dir

        # Execute patch
        stdout, stderr, status = Open3.capture3(*cmd, stdin_data: File.read(patch_file))

        if status.success?
          # Parse output to find affected files
          affected_files = stdout.scan(/patching file ['"]?([^'"]+)['"]?/).flatten.uniq

          {
            success: true,
            dry_run: dry_run,
            affected_files: affected_files,
            output: stdout
          }
        else
          raise FileOperationError, "Patch failed: #{stderr}"
        end
      rescue Errno::ENOENT
        raise FileOperationError, "patch command not found. Please install patch utility."
      end

      # Delete file with safety checks and backup
      # @param path [String] File path to delete
      # @param options [Hash] Options including :backup, :safety_check
      # @return [Hash] Result with backup path if created
      def delete_with_confirmation(path, options = {})
        create_backup_before = options.fetch(:backup, true)
        safety_check = options.fetch(:safety_check, true)

        unless File.exist?(path)
          return { success: false, reason: "File does not exist" }
        end

        # Safety check - only allow deletion within monadic/data
        if safety_check
          full_path = File.expand_path(path)
          unless PathConfig.safe_path?(full_path)
            raise SafetyError, "Cannot delete files outside of safe data directory"
          end
        end

        backup_path = nil
        if create_backup_before
          backup_path = create_backup(path)
        end

        # Delete the file
        File.delete(path)

        # Verify deletion
        if File.exist?(path)
          raise VerificationError, "File still exists after deletion"
        end

        {
          success: true,
          deleted: path,
          backup_path: backup_path
        }
      end

      # Verify file exists and has content
      # @param path [String] File path
      # @param min_size [Integer] Minimum file size in bytes
      # @return [Boolean] True if file exists and meets size requirement
      def verify_file_exists_with_size(path, min_size = 1)
        return false unless File.exist?(path)
        File.size(path) >= min_size
      end

      # Verify file content matches expected
      # @param path [String] File path
      # @param expected_content [String] Expected content
      # @param options [Hash] Options
      # @return [Boolean] True if content matches
      def verify_file_content(path, expected_content, options = {})
        return false unless File.exist?(path)

        ignore_whitespace = options.fetch(:ignore_whitespace, false)

        actual = File.read(path)
        expected = expected_content

        if ignore_whitespace
          actual = actual.strip.gsub(/\s+/, ' ')
          expected = expected.strip.gsub(/\s+/, ' ')
        end

        actual == expected
      end

      # Create atomic write (write to temp, then move)
      # @param path [String] Target file path
      # @param content [String] Content to write
      # @return [Hash] Result
      def atomic_write(path, content)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)

        # Create temp file in same directory (for atomic move)
        temp_file = Tempfile.new(['.autoforge_', '.tmp'], dir)

        begin
          temp_file.write(content)
          temp_file.close

          # Atomic move
          File.rename(temp_file.path, path)

          {
            success: true,
            path: path,
            size: File.size(path)
          }
        ensure
          temp_file.close! if temp_file
        end
      end

      private

      # Create backup of file
      # @param path [String] File to backup
      # @return [String] Backup file path
      def create_backup(path)
        backup_directory = self.class.backup_dir
        FileUtils.mkdir_p(backup_directory)

        timestamp = Time.now.strftime("%Y%m%d_%H%M%S_%L")
        basename = File.basename(path)
        backup_name = "#{basename}.#{timestamp}.backup"
        backup_path = File.join(backup_directory, backup_name)

        FileUtils.cp(path, backup_path)
        backup_path
      end

      # Restore file from backup
      # @param backup_path [String] Backup file path
      # @param target_path [String] Target restoration path
      def restore_from_backup(backup_path, target_path)
        unless File.exist?(backup_path)
          raise FileOperationError, "Backup file not found: #{backup_path}"
        end

        FileUtils.cp(backup_path, target_path)
      end
    end
  end
end