# frozen_string_literal: true

require 'json'

module Monadic
  module Utils
    module ModelDefaults
      # Model specifications with default values
      # Format: [[min, max], default] for ranges, or single default value
      MODEL_SPECS = {
        # Claude models
        "claude-opus-4-20250514" => {
          "max_output_tokens" => 32000
        },
        "claude-sonnet-4-20250514" => {
          "max_output_tokens" => 64000
        },
        "claude-3-7-sonnet-20250219" => {
          "max_output_tokens" => 64000
        },
        "claude-3-5-sonnet-20241022" => {
          "max_output_tokens" => 8192
        },
        "claude-3-opus-20240229" => {
          "max_output_tokens" => 4096
        },
        "claude-3-sonnet-20240229" => {
          "max_output_tokens" => 4096
        },
        "claude-3-haiku-20240307" => {
          "max_output_tokens" => 4096
        },
        # OpenAI models
        "gpt-4.5-preview" => {
          "max_output_tokens" => 16384
        },
        "gpt-4.5-preview-2025-02-27" => {
          "max_output_tokens" => 16384
        },
        "gpt-4.1" => {
          "max_output_tokens" => 32768
        },
        "gpt-4.1-mini" => {
          "max_output_tokens" => 32768
        },
        "gpt-4o" => {
          "max_output_tokens" => 16384
        },
        "gpt-4o-mini" => {
          "max_output_tokens" => 16384
        },
        "gpt-4-turbo" => {
          "max_output_tokens" => 4096
        },
        # Gemini models
        "gemini-2.5-flash" => {
          "max_output_tokens" => 32768
        },
        "gemini-2.5-pro" => {
          "max_output_tokens" => 32768
        },
        "gemini-2.0-flash" => {
          "max_output_tokens" => 8192
        },
        "gemini-1.5-pro" => {
          "max_output_tokens" => 8192
        },
        "gemini-1.5-flash" => {
          "max_output_tokens" => 8192
        },
        # Mistral models
        "mistral-large-latest" => {
          "max_output_tokens" => 131000
        },
        "pixtral-large-latest" => {
          "max_output_tokens" => 131000
        },
        "mistral-medium-2505" => {
          "max_output_tokens" => 64000
        },
        # Cohere models
        "command-r-plus" => {
          "max_output_tokens" => 4096
        },
        "command-r" => {
          "max_output_tokens" => 4096
        },
        # DeepSeek models
        "deepseek-chat" => {
          "max_output_tokens" => 8192
        },
        "deepseek-reasoner" => {
          "max_output_tokens" => 8192
        },
        # Grok models
        "grok-2" => {
          "max_output_tokens" => 16384
        },
        "grok-1" => {
          "max_output_tokens" => 8192
        },
        # Perplexity models
        "sonar" => {
          "max_output_tokens" => 8192
        },
        "sonar-reasoning" => {
          "max_output_tokens" => 131072
        }
      }.freeze

      # Default max_tokens if model not found
      DEFAULT_MAX_TOKENS = 4096

      # Get default max_tokens for a model
      def self.get_max_tokens(model_name)
        return DEFAULT_MAX_TOKENS if model_name.nil?
        
        # Try exact match first
        spec = MODEL_SPECS[model_name]
        return spec["max_output_tokens"] if spec
        
        # Try partial match (for models with dates)
        MODEL_SPECS.each do |key, value|
          return value["max_output_tokens"] if model_name.include?(key) || key.include?(model_name)
        end
        
        # Return default if no match found
        DEFAULT_MAX_TOKENS
      end
    end
  end
end