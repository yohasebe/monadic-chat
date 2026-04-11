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

require_relative '../utils/extra_logger'

module MonadicSharedTools
  module PythonExecution
    include MonadicHelper

    # Supported image extensions for _image enrichment (SVG excluded — not supported by ToolImageUtils)
    IMAGE_EXTENSIONS = %w[png jpg jpeg gif webp].freeze
    # Maximum file size for _image injection (5 MB)
    MAX_IMAGE_FILE_SIZE = 5 * 1024 * 1024
    # Maximum number of images to inject per tool call
    MAX_IMAGES_PER_CALL = 5

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
    def run_code(code:, command:, extension:, session: nil)
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

      # Call existing MonadicHelper implementation, passing the session
      output_json = super(code: code, command: command, extension: extension, session: session)

      # Parse output and store filename if successful (for continuous editing/analysis)
      if session && output_json.is_a?(String)
        begin
          # MonadicHelper#run_code typically returns a JSON string with success and filename fields
          parsed_output = JSON.parse(output_json)
          if parsed_output["success"] && parsed_output["filename"]
            session[:code_interpreter_last_output_file] = parsed_output["filename"]
          end
        rescue JSON::ParserError
          # Attempt to extract filename from raw output if not JSON (e.g., from image generation)
          if output_json =~ /File\(s\) generated.*?: ([^\s]+\.(?:png|jpg|jpeg|gif|svg|html))/i
            filename = $1
            session[:code_interpreter_last_output_file] = filename
          elsif output_json =~ /Created HTML file: ([^\s]+?\.html)/i
            filename = $1
            session[:code_interpreter_last_output_file] = filename
          end
        end
      end

      # Enrich output with _image if image files were generated
      enrich_with_images(output_json, session: session)
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

    private

    # Post-process run_code output: detect generated images and store gallery HTML
    # for server-side display via WebSocket (tool_html_fragments).
    #
    # Does NOT return _image key — vision injection into LLM context is intentionally
    # omitted for code execution tools. Injecting images as "user" messages triggers
    # additional API round-trips, causing tool-call loops. Gallery HTML ensures the
    # user sees images correctly without LLM involvement.
    #
    # Apps that need the LLM to see screenshots (browser automation, diagram preview)
    # return _image explicitly from their own tool methods.
    def enrich_with_images(output, session: nil)
      return output unless output.is_a?(String)

      # Extract /data/filename.ext patterns from the output
      image_basenames = output.scan(%r{/data/([\w\-. ]+\.(?:#{IMAGE_EXTENSIONS.join("|")}))})
                              .flatten
                              .uniq

      return output if image_basenames.empty?

      data_path = Monadic::Utils::Environment.data_path

      # Filter: file must exist and be ≤ MAX_IMAGE_FILE_SIZE
      valid_images = image_basenames.select do |basename|
        full_path = File.join(data_path, basename)
        File.exist?(full_path) && File.size(full_path) <= MAX_IMAGE_FILE_SIZE
      end.first(MAX_IMAGES_PER_CALL)

      return output if valid_images.empty?

      # Store gallery HTML for server-side injection via WebSocket.
      # This bypasses LLM filename hallucination — the correct <img> tags
      # are appended to the response regardless of what the LLM writes.
      if session
        gallery_html = valid_images.map { |img|
          "<div class=\"generated_image\"><img src=\"/data/#{img}\" /></div>"
        }.join("\n")
        session[:tool_html_fragments] ||= []
        session[:tool_html_fragments] << gallery_html
      end

      # Return original text — no _image key, no vision injection
      output
    end
  end
end
