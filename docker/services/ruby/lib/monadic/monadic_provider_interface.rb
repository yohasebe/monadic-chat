# frozen_string_literal: true

# Unified interface for monadic mode across all providers
module MonadicProviderInterface
  # Standard JSON schema for monadic responses
  MONADIC_JSON_SCHEMA = {
    "type" => "object",
    "properties" => {
      "message" => {
        "type" => "string",
        "description" => "The assistant's response to the user"
      },
      "context" => {
        "type" => "object",
        "description" => "Additional context and metadata",
        "properties" => {},
        "additionalProperties" => true
      }
    },
    "required" => ["message", "context"]
  }.freeze

  # Chat Plus specific schema extension
  CHAT_PLUS_SCHEMA = {
    "type" => "object",
    "properties" => {
      "message" => {
        "type" => "string",
        "description" => "Your response to the user"
      },
      "context" => {
        "type" => "object",
        "properties" => {
          "reasoning" => {
            "type" => "string",
            "description" => "The reasoning and thought process behind your response"
          },
          "topics" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "A list of topics discussed in the conversation"
          },
          "people" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "A list of people and their relationships mentioned"
          },
          "notes" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "Important information to remember"
          }
        },
        "required" => ["reasoning", "topics", "people", "notes"]
      }
    },
    "required" => ["message", "context"]
  }.freeze

  # Configure provider-specific JSON response format
  def configure_monadic_response(body, provider_type, app_type = nil)
    return body unless monadic_mode?

    case provider_type
    when :openai, :deepseek, :grok
      body["response_format"] = { "type" => "json_object" }
    when :perplexity
      body["response_format"] = build_perplexity_schema(app_type)
    when :claude
      # Claude uses system prompts, no body modification needed
    when :gemini
      configure_gemini_response(body, app_type)
    when :mistral, :cohere
      body["response_format"] = build_json_schema_format(app_type)
    when :ollama
      configure_ollama_response(body, app_type)
    end
    
    body
  end

  # Apply monadic transformation to user message for API
  def apply_monadic_transformation(message, app, role = "user")
    return message unless monadic_mode? && role == "user" && message && !message.empty?
    
    if defined?(APPS) && APPS[app]&.respond_to?(:monadic_unit)
      APPS[app].monadic_unit(message)
    else
      # Fallback to basic transformation
      JSON.generate({
        "message" => message,
        "context" => {}
      })
    end
  end

  # Process monadic response from provider
  def process_monadic_response(content, app)
    return content unless monadic_mode? && content && !content.empty?
    
    if defined?(APPS) && APPS[app]&.respond_to?(:monadic_map)
      APPS[app].monadic_map(content)
    else
      # Fallback to basic processing
      ensure_valid_monadic_json(content)
    end
  end

  # Validate and ensure response follows monadic schema
  def validate_monadic_response(response)
    return response unless monadic_mode?
    
    begin
      parsed = response.is_a?(String) ? JSON.parse(response) : response
      
      # Ensure required fields exist
      unless parsed.is_a?(Hash) && parsed.key?("message")
        parsed = {
          "message" => parsed.to_s,
          "context" => {}
        }
      end
      
      # Ensure context exists
      parsed["context"] ||= {}
      
      JSON.generate(parsed)
    rescue JSON::ParserError => e
      # Return safe fallback
      JSON.generate({
        "message" => response.to_s,
        "context" => {
          "error" => "Failed to parse response as JSON",
          "original_error" => e.message
        }
      })
    end
  end

  private

  def monadic_mode?
    @monadic_mode ||= (
      (defined?(@obj) && @obj["monadic"].to_s == "true") ||
      (defined?(obj) && obj["monadic"].to_s == "true")
    )
  end

  def build_perplexity_schema(app_type)
    schema = app_type&.to_s&.include?("chat_plus") ? CHAT_PLUS_SCHEMA : MONADIC_JSON_SCHEMA
    {
      "type" => "json_schema",
      "json_schema" => {
        "schema" => schema
      }
    }
  end

  def build_json_schema_format(app_type)
    schema = app_type&.to_s&.include?("chat_plus") ? CHAT_PLUS_SCHEMA : MONADIC_JSON_SCHEMA
    {
      "type" => "json_schema",
      "json_schema" => {
        "name" => "monadic_response",
        "schema" => schema
      }
    }
  end

  def configure_gemini_response(body, app_type)
    schema = app_type&.to_s&.include?("chat_plus") ? CHAT_PLUS_SCHEMA : MONADIC_JSON_SCHEMA
    
    body["generationConfig"] ||= {}
    body["generationConfig"]["responseMimeType"] = "application/json"
    body["generationConfig"]["responseSchema"] = schema
  end

  def configure_ollama_response(body, app_type)
    body["format"] = "json"
    
    # Add system instruction for JSON structure
    if body["messages"] && body["messages"].any?
      system_msg = body["messages"].find { |msg| msg["role"] == "system" }
      json_instruction = build_json_instruction(app_type)
      
      if system_msg
        system_msg["content"] += "\n\n" + json_instruction
      else
        body["messages"].unshift({
          "role" => "system",
          "content" => json_instruction
        })
      end
    end
  end

  def build_json_instruction(app_type)
    if app_type&.to_s&.include?("chat_plus")
      <<~TEXT
      You must respond with a JSON object following this exact structure:
      {
        "message": "Your response to the user",
        "context": {
          "reasoning": "The reasoning and thought process behind your response",
          "topics": ["List of topics discussed"],
          "people": ["List of people and their relationships mentioned"],
          "notes": ["Important information to remember"]
        }
      }
      TEXT
    else
      <<~TEXT
      You must respond with a JSON object following this structure:
      {
        "message": "Your response to the user",
        "context": {
          // Any relevant context information
        }
      }
      TEXT
    end
  end

  def ensure_valid_monadic_json(content)
    begin
      parsed = JSON.parse(content)
      if parsed.is_a?(Hash) && parsed.key?("message")
        content
      else
        JSON.generate({
          "message" => content,
          "context" => {}
        })
      end
    rescue JSON::ParserError
      JSON.generate({
        "message" => content,
        "context" => {}
      })
    end
  end
end