# frozen_string_literal: true

# Shared Python Execution Tools for Monadic Chat
# Provides code execution, bash commands, and environment inspection
#
# This module bridges existing MonadicHelper methods to shared tool interface.
# All implementations delegate to MonadicHelper for consistency.
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :python_execution, visibility: "always"
#   end
#
# Available tools:
#   - run_code: Execute Python/Ruby/Shell code
#   - run_bash_command: Execute bash commands in Python container
#   - check_environment: Inspect Docker container environment

module MonadicSharedTools
  module PythonExecution
    include MonadicHelper

    # Execute program code and return the output
    #
    # Delegates to MonadicHelper#run_code which handles:
    # - File creation with timestamp
    # - Docker container execution
    # - Output capture and error handling
    # - Automatic cleanup
    #
    # @param code [String] Program code to execute
    # @param command [String] Execution command (e.g., "python", "ruby", "bash")
    # @param extension [String] File extension (e.g., "py", "rb", "sh")
    # @return [String] Execution output or error message
    #
    # @example Execute Python code
    #   run_code(
    #     code: "print('Hello, World!')",
    #     command: "python",
    #     extension: "py"
    #   )
    #   # => "Hello, World!\nThe code has been executed successfully"
    #
    # @example Execute Ruby code
    #   run_code(
    #     code: "puts 'Hello from Ruby'",
    #     command: "ruby",
    #     extension: "rb"
    #   )
    def run_code(code:, command:, extension:)
      # Validate inputs
      unless code && command && extension
        return {
          success: false,
          error: "Missing required parameters: code, command, and extension are all required"
        }
      end

      # Validate code is not empty
      if code.to_s.strip.empty?
        return {
          success: false,
          error: "Code cannot be empty"
        }
      end

      # Call existing MonadicHelper implementation
      # Returns execution output as string
      output = super(code: code, command: command, extension: extension)

      # Return output directly (MonadicHelper already formats it)
      output
    end

    # Execute a bash command in the Python container
    #
    # Delegates to MonadicHelper#run_bash_command which uses send_command
    # to execute commands in the isolated Python Docker container.
    #
    # @param command [String] Bash command to execute
    # @return [String] Command output or error message
    #
    # @example List files
    #   run_bash_command(command: "ls -la /monadic/data")
    #
    # @example Install package
    #   run_bash_command(command: "pip install requests")
    #
    # @example Check Python version
    #   run_bash_command(command: "python --version")
    def run_bash_command(command:)
      # Validate input
      unless command
        return {
          success: false,
          error: "Command parameter is required"
        }
      end

      if command.to_s.strip.empty?
        return {
          success: false,
          error: "Command cannot be empty"
        }
      end

      # Call existing MonadicHelper implementation
      super(command: command)
    end

    # Check the Python container environment configuration
    #
    # Returns Dockerfile and pysetup.sh contents to help users understand
    # the execution environment, installed packages, and configuration.
    #
    # Delegates to MonadicHelper#check_environment which fetches:
    # - Dockerfile: Container build configuration
    # - pysetup.sh: Python package installation script
    #
    # @return [String] Formatted environment information with code blocks
    #
    # @example Check environment
    #   check_environment()
    #   # => "### Dockerfile\n```\nFROM python:3.11...\n```\n\n### pysetup.sh\n```\n#!/bin/bash..."
    def check_environment
      # Call existing MonadicHelper implementation
      # Returns formatted markdown with Dockerfile and pysetup.sh contents
      super()
    end

    # Install a library using package manager
    #
    # Delegates to MonadicHelper#lib_installer for package installation
    # in the Python container. Supports pip, uv, and apt package managers.
    #
    # @param command [String] Package name(s) to install
    # @param packager [String] Package manager to use ("pip", "uv", or "apt")
    # @return [String] Installation output
    #
    # @example Install with pip
    #   lib_installer(command: "numpy pandas", packager: "pip")
    #
    # @example Install with uv (faster pip alternative)
    #   lib_installer(command: "matplotlib", packager: "uv")
    #
    # @example Install system package
    #   lib_installer(command: "ffmpeg", packager: "apt")
    def lib_installer(command:, packager: "pip")
      # Call existing MonadicHelper implementation
      super(command: command, packager: packager)
    end
  end
end
