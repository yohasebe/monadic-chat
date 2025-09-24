# GPT-5-Codex Agent Module
# Shared functionality for calling GPT-5-Codex from various apps
#
# This module provides a common implementation for apps that need to
# delegate complex coding tasks to GPT-5-Codex via the Responses API.

module Monadic
  module Agents
    module GPT5CodexAgent
      # Call GPT-5-Codex agent for complex coding tasks
      # @param prompt [String] The complete prompt to send to GPT-5-Codex
      # @param app_name [String] Name of the calling app for logging (optional)
      # @return [Hash] Response with :code, :success, :model, and optionally :error
      def call_gpt5_codex(prompt:, app_name: nil)
        begin
          if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            app_label = app_name || self.class.name
            puts "#{app_label}: Calling GPT-5-Codex agent"
            puts "Prompt length: #{prompt.length} chars"
          end

          # Check if OpenAIHelper is available
          unless defined?(OpenAIHelper) && self.class.included_modules.include?(OpenAIHelper)
            return {
              error: "OpenAIHelper not available",
              success: false
            }
          end

          # Create a proper session object for the API call
          # api_request expects messages with "text" field, not "content"
          session = {
            parameters: {
              "model" => "gpt-5-codex",
              "max_completion_tokens" => 128000,  # GPT-5-Codex max output
              "temperature" => 0.0  # Deterministic for code generation
            },
            messages: [
              {
                "role" => "user",
                "text" => prompt,
                "active" => true
              }
            ]
          }

          # Call api_request which will properly detect this is a Responses API model
          results = api_request("user", session, call_depth: 0)

          # Parse the response
          if results && results.is_a?(Array) && results.first
            response = results.first
            content = if response.is_a?(Hash)
                        response["content"] || response[:content] || response.dig("choices", 0, "message", "content")
                      else
                        response.to_s
                      end

            {
              code: content,
              success: true,
              model: "gpt-5-codex"
            }
          else
            {
              error: "No response from GPT-5-Codex",
              success: false
            }
          end

        rescue StandardError => e
          {
            error: "Error calling GPT-5-Codex: #{e.message}",
            suggestion: "Try breaking the task into smaller pieces",
            success: false
          }
        end
      end

      # Build a minimal prompt for GPT-5-Codex following "less is more" principle
      # @param task [String] The main task description
      # @param options [Hash] Optional context to add to the prompt
      # @option options [String] :current_code Current code for debugging/refactoring
      # @option options [String] :error_context Error message to fix
      # @option options [String] :context Additional context
      # @option options [Array<Hash>] :files Array of file objects with :path and :content
      # @return [String] The built prompt
      def build_codex_prompt(task:, **options)
        prompt = task

        # Add current code context if debugging/refactoring
        if options[:current_code] && !options[:current_code].empty?
          prompt += "\n\nCurrent code:\n```\n#{options[:current_code]}\n```"
        end

        # Add error context if fixing issues
        if options[:error_context] && !options[:error_context].empty?
          prompt += "\n\nError to fix:\n#{options[:error_context]}"
        end

        # Add file context if provided (limited to avoid token overflow)
        if options[:files] && !options[:files].empty? && options[:files].is_a?(Array)
          prompt += "\n\nFiles to consider:\n"
          options[:files].take(3).each do |file|  # Limit to 3 files
            if file.is_a?(Hash) && file[:path] && file[:content]
              # Limit content to 1000 chars per file
              content_preview = file[:content].to_s[0..1000]
              prompt += "\n#{file[:path]}:\n```\n#{content_preview}\n```\n"
            end
          end
        end

        # Add general context if provided
        if options[:context] && !options[:context].empty?
          prompt += "\n\nContext: #{options[:context]}"
        end

        prompt
      end
    end
  end
end