# frozen_string_literal: true

require_relative 'core'
require_relative 'json_handler'
require_relative 'html_renderer'

module MonadicChat
  # Extensions for MonadicApp to maintain backward compatibility
  # while providing clean, modular implementation
  module AppExtensions
    include Core
    include JsonHandler
    include HtmlRenderer
    
    # Initialize monadic functionality
    def self.included(base)
      # No initialization needed - methods are defined directly in the module
    end
    
    # == Backward Compatible Methods ==
    
    # Wrap the user's message in a monad (maintains exact original behavior)
    def monadic_unit(message)
      wrap_as_json(message, @context)
    end
    
    # Unwrap the monad and return the message (maintains exact original behavior)
    def monadic_unwrap(monad)
      unwrap_from_json(monad)
    end
    
    # Unwrap the monad and return the message after applying a given process
    def monadic_map(monad, &block)
      transform_json(monad, &block)
    end
    
    # Convert a monad to HTML (maintains exact original behavior)
    def monadic_html(monad)
      render_as_html(monad, settings)
    end
    
    # Alias for backward compatibility - maintain original signature
    def json2html(hash, iteration: 0, exclude_empty: true, mathjax: false)
      settings = {
        iteration: iteration,
        exclude_empty: exclude_empty,
        mathjax: mathjax
      }
      json_to_html(hash, settings)
    end
    
    # == Enhanced Methods (New Functionality) ==
    
    # Create a pure monadic value (FP style)
    def monadic_pure(value)
      wrap(value, @context || {})
    end
    
    # Bind operation (flatMap in FP terms)
    def monadic_bind(monad, &block)
      parsed = unwrap_from_json(monad)
      value = parsed["message"] || parsed["value"]
      context = parsed["context"] || @context || {}
      
      # Apply function that returns a new monad
      result = yield(value, context)
      
      # Ensure result is properly formatted
      case result
      when String
        begin
          JSON.parse(result)
          result
        rescue JSON::ParserError
          monadic_unit(result)
        end
      when Hash
        result.to_json
      else
        monadic_unit(result.to_s)
      end
    end
    
    # Check if value is monadic
    def monadic?(value)
      case value
      when String
        begin
          parsed = JSON.parse(value)
          parsed.is_a?(Hash) && (parsed.key?("message") || parsed.key?("value"))
        rescue JSON::ParserError
          false
        end
      when Hash
        value.key?("message") || value.key?("value")
      else
        false
      end
    end
    
    # == Context Management ==
    
    # Get current context
    def monadic_context
      @context ||= {}
    end
    
    # Update context
    def monadic_context=(new_context)
      @context = new_context
    end
    
    # Merge additional context
    def monadic_merge_context(additional)
      @context = (@context || {}).merge(additional)
    end
    
    # == Validation and Error Handling ==
    
    # Validate monadic structure
    def validate_monadic_structure(monad, expected_structure = nil)
      parsed = unwrap_from_json(monad)
      
      # Basic validation
      unless parsed.is_a?(Hash)
        return { valid: false, errors: ["Not a valid hash structure"] }
      end
      
      unless parsed.key?("message") || parsed.key?("value")
        return { valid: false, errors: ["Missing 'message' or 'value' field"] }
      end
      
      # Structure validation if provided
      if expected_structure
        errors = validate_json_structure(parsed, expected_structure)
        return { valid: errors.empty?, errors: errors }
      end
      
      { valid: true, errors: [] }
    end
    
    # == Debugging Support ==
    
    # Get monadic debug information
    def monadic_debug_info(monad)
      {
        type: monad.class.name,
        valid_json: monadic?(monad),
        structure: begin
          unwrap_from_json(monad)
        rescue
          "Invalid structure"
        end,
        context: @context
      }
    end
    
    private
    
    # Helper to access settings safely
    def settings
      @settings || {}
    end
  end
end