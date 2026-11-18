# frozen_string_literal: true

require 'cgi'
require 'shellwords'

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

require_relative '../utils/extra_logger'
require_relative '../workbench/chat_output'

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
    #
    # The code runs in a run folder of the chat's folder: what it writes by a
    # plain name stays there and is shown on the work screen beside the
    # chat. Without a chat it does not run.
    def run_code(code:, command:, extension:, session: nil, workbench: nil)
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

      job = code_run_folder(session, workbench)
      return NO_CHAT_FOLDER unless job

      output = super(code: code, command: command, extension: extension, session: session, run_dir: job)
      output + run_folder_notice(job, workbench)
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
    def run_bash_command(command:, session: nil, workbench: nil)
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

      # Defensive warning: models occasionally misuse `~/monadic/data`
      # (the host-side path the user sees) instead of `/data` (the
      # container path) because the system prompt mentions both. Inside
      # the container, `~` expands to `/root`, so the lookup silently
      # fails and the model may improvise with fake data. Flag this in
      # the logs so the MDSL PATH CONVENTIONS guidance can be audited.
      # See code_interpreter_claude.mdsl "PATH CONVENTIONS" block.
      if command.to_s.include?('~/monadic/data')
        Monadic::Utils::ExtraLogger.log {
          "[PythonExecution] ~/monadic/data detected in run_bash_command — model likely confused container vs host paths. Command: #{command.to_s[0..200]}"
        }
      end

      # The command runs in a run folder of the chat's folder, so what it
      # writes by a plain name stays in the chat (never at the top of the
      # shared folder).
      job = code_run_folder(session, workbench)
      return NO_CHAT_FOLDER unless job

      folder = File.join(Monadic::Utils::SharedPathGuard::CONTAINER_ROOT, job[:relative])
      output = super(command: "cd #{Shellwords.escape(folder)} && #{command}")
      output.to_s + run_folder_notice(job, workbench)
    end

    # Check the Python container environment configuration
    #
    # Returns the Dockerfile contents to help users understand the execution
    # environment, installed packages, and configuration.
    #
    # Delegates to MonadicHelper#check_environment which fetches:
    # - Dockerfile: Container build configuration
    #
    # @return [String] Formatted environment information with code blocks
    #
    # @example Check environment
    #   check_environment()
    #   # => "### Dockerfile\n```\nFROM python:3.12...\n```\n..."
    def check_environment
      # Call existing MonadicHelper implementation
      # Returns formatted markdown with the Dockerfile contents
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

    private

    NO_CHAT_FOLDER = "Error: There is no chat folder to run this in."

    # A run folder of the chat for this run, or nil without a chat.
    def code_run_folder(session, workbench)
      app_name = session&.dig(:parameters, "app_name")
      Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: workbench, app_name: app_name || self.class.name)
    end

    # What the model is told of the files the run left: shown on the work
    # screen, by their paths. A run that left nothing leaves no folder.
    def run_folder_notice(job, workbench)
      taken = Monadic::Workbench::ChatOutput.take_all(job, workbench)
      if taken[:paths].empty?
        Monadic::Workbench::ChatOutput.drop_if_empty(job)
        return ""
      end

      listed = taken[:paths].map { |path| "- #{path}" }.join("\n")
      if taken[:shown]
        "\n\nThese files are shown on the work screen beside the chat:\n#{listed}\n" \
          "In your reply, name them in one short line with their paths; do not embed them in the reply. " \
          "To read one in later code, open /monadic/data/ followed by its path."
      else
        "\n\nThese files were saved, but the work screen could not show them all; give the user their paths:\n#{listed}"
      end
    end

  end
end
