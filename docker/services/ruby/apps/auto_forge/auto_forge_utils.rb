# frozen_string_literal: true

require 'fileutils'
require 'time'
require 'json'
require_relative 'utils/path_config'

# Utility module for AutoForge project management
module AutoForgeUtils
  class ProjectCreationError < StandardError; end

  # Create a timestamped project directory
  # @param base_name [String] Base name for the project
  # @param metadata [Hash] Optional metadata to store in project
  # @return [Hash] Project information including name and path
  def self.create_project_directory(base_name, metadata = {})
    raise ProjectCreationError, "Project name is required" if base_name.nil? || base_name.strip.empty?

    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    # Allow Unicode letters, numbers, and common CJK characters, plus ASCII alphanumerics
    # Remove only truly problematic characters for filesystems
    safe_name = base_name.strip
                        .gsub(/[<>:"|?*\\\/]/, '_')  # Remove filesystem-unsafe characters
                        .gsub(/[\x00-\x1f\x7f]/, '_')  # Remove control characters
                        .gsub(/\.{2,}/, '_')            # Replace multiple dots
                        .gsub(/_{2,}/, '_')             # Replace multiple underscores
                        .gsub(/^[._]|[._]$/, '')       # Remove leading/trailing dots or underscores

    # Ensure name is not empty after sanitization
    safe_name = 'app' if safe_name.empty?

    project_name = "#{safe_name}_#{timestamp}"

    base_path = AutoForge::Utils::PathConfig.project_base_path
    project_path = File.join(base_path, project_name)

    # Create directory
    FileUtils.mkdir_p(project_path)

    # Store metadata if provided
    if metadata.any?
      metadata_file = File.join(project_path, ".autoforge.json")
      full_metadata = metadata.merge(
        created_at: Time.now.iso8601,
        project_name: project_name,
        base_name: base_name
      )
      File.write(metadata_file, JSON.pretty_generate(full_metadata))
    end

    {
      name: project_name,
      path: project_path,
      base_name: base_name,
      created_at: Time.now.iso8601,
      metadata: metadata
    }
  rescue Errno::EACCES => e
    raise ProjectCreationError, "Permission denied creating project directory: #{e.message}"
  rescue => e
    raise ProjectCreationError, "Failed to create project directory: #{e.message}"
  end

  # List existing AutoForge projects
  # @return [Array<Hash>] List of project information
  def self.list_projects
    base_path = AutoForge::Utils::PathConfig.project_base_path
    return [] unless File.directory?(base_path)

    Dir.glob(File.join(base_path, "*")).select { |f| File.directory?(f) }.map do |dir|
      project_name = File.basename(dir)
      metadata_file = File.join(dir, ".autoforge.json")

      metadata = if File.exist?(metadata_file)
        JSON.parse(File.read(metadata_file), symbolize_names: true)
      else
        {}
      end

      # Check if index.html exists
      has_index = File.exist?(File.join(dir, "index.html"))

      {
        name: project_name,
        path: dir,
        created_at: metadata[:created_at] || File.stat(dir).ctime.iso8601,
        metadata: metadata,
        has_index: has_index,
        base_name: metadata[:base_name] || project_name.sub(/_\d{8}_\d{6}$/, '')
      }
    end.sort_by { |p| p[:created_at] }.reverse
  end

  # Find most recent project by base name
  # @param base_name [String] Base name to search for
  # @return [Hash, nil] Project information or nil if not found
  def self.find_recent_project(base_name)
    return nil if base_name.nil? || base_name.strip.empty?

    projects = list_projects
    projects.find do |project|
      project[:base_name].casecmp?(base_name.strip) ||
      project[:name].casecmp?(base_name.strip)
    end
  end

  # Clean up old projects (older than days_old)
  # @param days_old [Integer] Number of days to keep projects
  # @return [Array<String>] List of removed project names
  def self.cleanup_old_projects(days_old = 7)
    cutoff_time = Time.now - (days_old * 24 * 60 * 60)
    removed = []

    list_projects.each do |project|
      created_at = Time.parse(project[:created_at])
      if created_at < cutoff_time
        FileUtils.rm_rf(project[:path])
        removed << project[:name]
      end
    end

    removed
  end

  # Validate project specification
  # @param spec [Hash] Project specification
  # @return [Hash] Validation result with :valid and :errors keys
  def self.validate_spec(spec)
    errors = []

    # Check if spec is a hash
    unless spec.is_a?(Hash)
      errors << "Specification must be a hash"
      return { valid: false, errors: errors }
    end

    # Convert string keys to symbols if needed
    spec = spec.transform_keys(&:to_sym) if spec.respond_to?(:transform_keys)

    # Check required fields as per system prompt
    unless spec[:name] && !spec[:name].to_s.strip.empty?
      errors << "Project name is required"
    end

    unless spec[:type] && !spec[:type].to_s.strip.empty?
      errors << "Project type is required"
    end

    unless spec[:description] && !spec[:description].to_s.strip.empty?
      errors << "Project description is required"
    end

    unless spec[:features] && spec[:features].is_a?(Array) && !spec[:features].empty?
      errors << "Features array is required and must not be empty"
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end

  # Validate multi-file project specification (for future use)
  # @param spec [Hash] Project specification with files array
  # @return [Hash] Validation result with :valid and :errors keys
  def self.validate_multi_file_spec(spec)
    errors = []

    # Check required fields
    errors << "Project name is required" unless spec[:name] && !spec[:name].strip.empty?
    errors << "Files list is required" unless spec[:files] && spec[:files].is_a?(Array)

    if spec[:files] && spec[:files].is_a?(Array)
      if spec[:files].empty?
        errors << "At least one file must be specified"
      else
        spec[:files].each_with_index do |file, index|
          unless file[:name] && !file[:name].strip.empty?
            errors << "File ##{index + 1}: name is required"
          end
          unless file[:description] && !file[:description].strip.empty?
            errors << "File ##{index + 1} (#{file[:name]}): description is required"
          end
        end
      end

      # Check for duplicate file names
      file_names = spec[:files].map { |f| f[:name] }.compact
      duplicates = file_names.select { |name| file_names.count(name) > 1 }.uniq
      errors << "Duplicate file names: #{duplicates.join(', ')}" if duplicates.any?
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end
end
