# frozen_string_literal: true

require 'ostruct'

# Shared Tool Registry for Monadic Chat
# Centralizes tool group definitions with metadata for Progressive Tool Disclosure
#
# This registry provides:
# - Tool specifications (name, description, parameters)
# - Default unlock hints for PTD
# - Module references for implementation
#
# Usage:
#   MonadicSharedTools::Registry.tools_for(:file_operations)
#   # => [#<OpenStruct name="read_file_from_shared_folder", ...>, ...]

module MonadicSharedTools
  class Registry
    # Tool group definitions with complete metadata
    # Each group contains:
    # - module: The Ruby module containing the implementation
    # - tools: Array of tool specifications (name, description, parameters)
    # - default_hint: Default PTD unlock hint for this group
    TOOL_GROUPS = {
      file_operations: {
        module_name: 'MonadicSharedTools::FileOperations',
        tools: [
          {
            name: "read_file_from_shared_folder",
            description: "Read a file from the shared folder and return its content with metadata",
            parameters: [
              {
                name: :filepath,
                type: "string",
                description: "Relative or absolute path to the file (e.g., 'reports/summary.md')",
                required: true
              }
            ]
          },
          {
            name: "write_file_to_shared_folder",
            description: "Write or append content to a file in the shared folder with Unicode and subdirectory support",
            parameters: [
              {
                name: :filepath,
                type: "string",
                description: "Path to the file (relative to shared folder or absolute). Supports subdirectories and Unicode characters (e.g., 'プロジェクト/2025年/レポート.md')",
                required: true
              },
              {
                name: :content,
                type: "string",
                description: "Content to write to the file",
                required: true
              },
              {
                name: :mode,
                type: "string",
                description: "Write mode: 'write' to overwrite or 'append' to add to existing file (default: 'write')",
                required: false
              }
            ]
          },
          {
            name: "list_files_in_shared_folder",
            description: "List all files and directories in the shared folder or a subdirectory",
            parameters: [
              {
                name: :directory,
                type: "string",
                description: "Subdirectory to list (optional, defaults to root folder)",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"file_operations\") when you need to read, write, or list files in the shared folder."
      }

      # Future tool groups will be added here:
      # web_tools: { ... },
      # python_execution: { ... },
      # app_creation: { ... }
    }

    # Get tool specifications for a given tool group
    #
    # @param group [Symbol] Tool group name (e.g., :file_operations)
    # @return [Array<OpenStruct>] Array of tool specification objects
    # @raise [ArgumentError] if group is unknown
    # @example
    #   tools = Registry.tools_for(:file_operations)
    #   tools.first.name # => "read_file_from_shared_folder"
    #   tools.first.description # => "Read a file from..."
    #   tools.first.parameters # => [{name: :filepath, type: "string", ...}]
    def self.tools_for(group)
      config = TOOL_GROUPS[group]
      raise ArgumentError, "Unknown tool group: #{group}. Available groups: #{TOOL_GROUPS.keys.join(', ')}" unless config

      # Convert tool specs to OpenStruct for easy access
      config[:tools].map do |spec|
        OpenStruct.new(spec)
      end
    end

    # Get the module name for a given tool group
    #
    # @param group [Symbol] Tool group name
    # @return [String] Module name
    # @raise [ArgumentError] if group is unknown
    # @example
    #   Registry.module_name_for(:file_operations)
    #   # => "MonadicSharedTools::FileOperations"
    def self.module_name_for(group)
      config = TOOL_GROUPS[group]
      raise ArgumentError, "Unknown tool group: #{group}" unless config

      config[:module_name]
    end

    # Get the default unlock hint for a given tool group
    #
    # @param group [Symbol] Tool group name
    # @return [String] Default unlock hint
    # @raise [ArgumentError] if group is unknown
    # @example
    #   Registry.default_hint_for(:file_operations)
    #   # => "Call request_tool(\"file_operations\") when you need to..."
    def self.default_hint_for(group)
      config = TOOL_GROUPS[group]
      return "" unless config

      config[:default_hint]
    end

    # Get all available tool group names
    #
    # @return [Array<Symbol>] List of tool group names
    # @example
    #   Registry.available_groups
    #   # => [:file_operations]
    def self.available_groups
      TOOL_GROUPS.keys
    end

    # Check if a tool group exists
    #
    # @param group [Symbol] Tool group name
    # @return [Boolean] true if group exists
    # @example
    #   Registry.group_exists?(:file_operations) # => true
    #   Registry.group_exists?(:unknown)          # => false
    def self.group_exists?(group)
      TOOL_GROUPS.key?(group)
    end
  end
end
