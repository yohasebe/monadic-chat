# frozen_string_literal: true

require_relative "../utils/system_defaults"
require "net/http"
require "uri"
require "json"
require "cld"

# Context Extractor Agent
# Automatically extracts conversation context after each response for apps with monadic: true setting
# Now supports app-specific context schemas defined in MDSL via context_schema block
#
# IMPORTANT: This module uses direct HTTP API calls instead of send_query to avoid
# re-triggering the WebSocket message flow, which would cause infinite loops.
module ContextExtractorAgent
  # Default schema for apps without explicit context_schema
  DEFAULT_SCHEMA = {
    fields: [
      { name: "topics", icon: "fa-tags", label: "Topics", description: "Main subjects discussed" },
      { name: "people", icon: "fa-users", label: "People", description: "Names of people mentioned" },
      { name: "notes", icon: "fa-sticky-note", label: "Notes", description: "Important facts to remember" }
    ]
  }.freeze

  # Build dynamic extraction prompt based on context schema
  # @param schema [Hash] The context schema
  # @param language [String] The conversation language code (e.g., "ja", "en", "auto")
  # @param detected_language [String] The detected language when language is "auto"
  def build_extraction_prompt(schema, language = nil, detected_language = nil)
    fields = schema[:fields] || schema["fields"] || DEFAULT_SCHEMA[:fields]

    field_descriptions = fields.map do |field|
      name = field[:name] || field["name"]
      desc = field[:description] || field["description"]
      "- #{name}: #{desc} (brief phrases, 2-5 words each)"
    end.join("\n")

    json_example = fields.map do |field|
      name = field[:name] || field["name"]
      "\"#{name}\":[\"example1\",\"example2\"]"
    end.join(",")

    # Build language instruction
    effective_language = if language && language != "auto"
      language
    else
      detected_language
    end

    language_instruction = if effective_language
      lang_name = case effective_language
        when "ja" then "Japanese"
        when "zh" then "Chinese"
        when "ko" then "Korean"
        when "es" then "Spanish"
        when "fr" then "French"
        when "de" then "German"
        when "pt" then "Portuguese"
        when "it" then "Italian"
        when "ru" then "Russian"
        when "ar" then "Arabic"
        when "hi" then "Hindi"
        when "th" then "Thai"
        when "vi" then "Vietnamese"
        when "en" then "English"
        else effective_language.upcase
      end
      "- IMPORTANT: Output ALL extracted items in #{lang_name} only. Do not mix languages."
    else
      "- Output extracted items in the same language as the conversation"
    end

    <<~PROMPT
      You are a context extraction assistant. Analyze the conversation and extract key information.

      Return ONLY a valid JSON object with this exact structure (no markdown, no explanation):
      {#{json_example}}

      Fields to extract:
      #{field_descriptions}

      Rules:
      - Include only NEW information from this exchange
      - Use empty arrays [] for categories with no new information
      - Keep items concise and relevant
      #{language_instruction}
      - IMPORTANT: Normalize and deduplicate entities - do not include variations of the same item
        - For people: Use the most complete or formal name mentioned (e.g., "田中太郎" not both "田中" and "田中太郎")
        - For topics: Use canonical form without honorifics or casual variations
        - For any category: If two items refer to the same entity, include only one
    PROMPT
  end

  # API endpoints for different providers
  API_ENDPOINTS = {
    "openai" => "https://api.openai.com/v1/chat/completions",
    "anthropic" => "https://api.anthropic.com/v1/messages",
    "gemini" => "https://generativelanguage.googleapis.com/v1beta/models/%{model}:generateContent",
    "xai" => "https://api.x.ai/v1/chat/completions",
    "mistral" => "https://api.mistral.ai/v1/chat/completions",
    "cohere" => "https://api.cohere.ai/v2/chat",
    "deepseek" => "https://api.deepseek.com/v1/chat/completions",
    "ollama" => "http://ollama:11434/api/chat"
  }.freeze

  # Detect the dominant language of the conversation text
  # Uses CLD (Compact Language Detector) gem for accurate detection
  # @param text [String] The text to analyze
  # @return [String] The detected language code (e.g., "ja", "zh", "ko", "en", "fr", "de", etc.)
  def detect_conversation_language(text)
    return "en" if text.nil? || text.empty?

    # Use the CLD gem for accurate language detection
    CLD.detect_language(text)[:code]
  rescue StandardError => e
    puts "[ContextExtractor] Language detection error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    "en"  # Default to English on error
  end

  # Extract context from a conversation exchange using direct HTTP API calls
  # @param session [Hash] The session information
  # @param user_message [String] The user's message
  # @param assistant_response [String] The assistant's response
  # @param provider [String] The AI provider to use
  # @param schema [Hash] The context schema defining fields to extract (optional)
  # @param language [String] The conversation language code (optional)
  # @return [Hash, nil] Extracted context or nil on failure
  def extract_context(session, user_message, assistant_response, provider, schema = nil, language = nil)
    provider = normalize_provider(provider)

    # Debug: Log provider normalization
    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] extract_context called with provider=#{provider}")
      end
    end

    model = SystemDefaults.get_default_model(provider)

    # For Ollama, try to get the first available model if no default is configured
    if model.nil? && provider == "ollama"
      model = get_ollama_fallback_model
    end

    # Debug: Log model lookup result
    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] model lookup result: model=#{model.inspect}")
      end
    end

    if model.nil?
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] EARLY RETURN: model is nil for provider=#{provider}")
        end
      end
      return nil
    end

    # Check API key availability (Ollama doesn't need API key)
    api_key = get_api_key_for_provider(provider)

    # Debug: Log API key check
    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] API key present: #{!api_key.nil? && !api_key.empty?}")
      end
    end

    if api_key.nil? && provider != "ollama"
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] EARLY RETURN: no API key for provider=#{provider}")
        end
      end
      return nil
    end

    # Use provided schema or default
    effective_schema = schema || DEFAULT_SCHEMA

    # Detect language from conversation if language is "auto" or nil
    detected_language = nil
    if language.nil? || language == "auto"
      # Detect language from the combined conversation text
      conversation_for_detection = "#{user_message}\n#{assistant_response}"
      detected_language = detect_conversation_language(conversation_for_detection)
      puts "[ContextExtractor] Detected language: #{detected_language}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    end

    # Build the extraction prompt dynamically with language support
    extraction_prompt = build_extraction_prompt(effective_schema, language, detected_language)

    conversation_text = <<~TEXT
      User: #{user_message}

      Assistant: #{assistant_response}
    TEXT

    system_message = "#{extraction_prompt}\n\nConversation to analyze:\n#{conversation_text}"

    begin
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] Calling API: provider=#{provider}, model=#{model}")
        end
      end

      result = call_provider_api(provider, model, system_message, api_key)

      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] API result: #{result.nil? ? 'nil' : "#{result.length} chars"}")
        end
      end

      if result.is_a?(String) && !result.empty?
        parsed = parse_context_json(result, effective_schema)
        if CONFIG && CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts("[#{Time.now}] [ContextExtractor] Parsed context: #{parsed.inspect}")
          end
        end
        parsed
      else
        if CONFIG && CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
            log.puts("[#{Time.now}] [ContextExtractor] API returned empty or nil result")
          end
        end
        nil
      end
    rescue StandardError => e
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] API exception: #{e.class}: #{e.message}")
        end
      end
      log_extraction_error(provider, model, e)
      nil
    end
  end

  # Make direct HTTP API call to the provider
  # @param provider [String] The provider name
  # @param model [String] The model to use
  # @param system_message [String] The system message containing the prompt
  # @param api_key [String] The API key (nil for Ollama)
  # @return [String, nil] The response text or nil
  def call_provider_api(provider, model, system_message, api_key)
    case provider
    when "openai", "xai", "mistral", "deepseek"
      call_openai_compatible_api(provider, model, system_message, api_key)
    when "anthropic"
      call_anthropic_api(model, system_message, api_key)
    when "gemini"
      call_gemini_api(model, system_message, api_key)
    when "cohere"
      call_cohere_api(model, system_message, api_key)
    when "ollama"
      call_ollama_api(model, system_message)
    else
      # Default to OpenAI-compatible format
      call_openai_compatible_api(provider, model, system_message, api_key)
    end
  end

  # Call OpenAI-compatible API (OpenAI, xAI, Mistral, DeepSeek)
  def call_openai_compatible_api(provider, model, system_message, api_key)
    endpoint = API_ENDPOINTS[provider] || API_ENDPOINTS["openai"]
    uri = URI.parse(endpoint)

    request_body = {
      "model" => model,
      "messages" => [
        { "role" => "system", "content" => system_message },
        { "role" => "user", "content" => "Extract context and return JSON only." }
      ]
    }

    # Handle OpenAI-specific parameters based on model
    if provider == "openai"
      request_body["max_completion_tokens"] = 500

      # GPT-5 models don't support temperature, use reasoning_effort instead
      if model.start_with?("gpt-5")
        # Use "none" for all GPT-5 variants (context extraction is a simple task)
        request_body["reasoning_effort"] = "none"
      else
        # Other OpenAI models (gpt-4.1, etc.) support temperature
        request_body["temperature"] = 0.3
      end
    else
      # Other providers (xAI, Mistral, DeepSeek) use max_tokens and temperature
      request_body["max_tokens"] = 500
      request_body["temperature"] = 0.3
    end

    response = make_http_request(uri, request_body, {
      "Authorization" => "Bearer #{api_key}",
      "Content-Type" => "application/json"
    })

    return nil unless response

    data = JSON.parse(response)
    data.dig("choices", 0, "message", "content")
  rescue StandardError => e
    puts "[ContextExtractor] OpenAI-compatible API error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Call Anthropic API
  def call_anthropic_api(model, system_message, api_key)
    uri = URI.parse(API_ENDPOINTS["anthropic"])

    request_body = {
      "model" => model,
      "system" => system_message,
      "messages" => [
        { "role" => "user", "content" => "Extract context and return JSON only." }
      ],
      "max_tokens" => 500,
      "temperature" => 0.3
    }

    response = make_http_request(uri, request_body, {
      "x-api-key" => api_key,
      "anthropic-version" => "2023-06-01",
      "Content-Type" => "application/json"
    })

    return nil unless response

    data = JSON.parse(response)
    content = data.dig("content", 0)
    content["text"] if content && content["type"] == "text"
  rescue StandardError => e
    puts "[ContextExtractor] Anthropic API error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Call Gemini API
  def call_gemini_api(model, system_message, api_key)
    endpoint = API_ENDPOINTS["gemini"] % { model: model }
    uri = URI.parse("#{endpoint}?key=#{api_key}")

    request_body = {
      "contents" => [
        {
          "parts" => [
            { "text" => "#{system_message}\n\nExtract context and return JSON only." }
          ]
        }
      ],
      "generationConfig" => {
        "maxOutputTokens" => 500,
        "temperature" => 0.3
      }
    }

    response = make_http_request(uri, request_body, {
      "Content-Type" => "application/json"
    })

    return nil unless response

    data = JSON.parse(response)
    data.dig("candidates", 0, "content", "parts", 0, "text")
  rescue StandardError => e
    puts "[ContextExtractor] Gemini API error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Call Cohere API
  def call_cohere_api(model, system_message, api_key)
    uri = URI.parse(API_ENDPOINTS["cohere"])

    # Check if this is a reasoning/thinking model
    is_reasoning_model = model.to_s.include?("reasoning") || model.to_s.include?("command-a")

    request_body = {
      "model" => model,
      "messages" => [
        { "role" => "system", "content" => system_message },
        { "role" => "user", "content" => "Extract context and return JSON only." }
      ],
      "max_tokens" => 500
    }

    # Reasoning models don't support temperature, but require thinking parameter
    if is_reasoning_model
      request_body["thinking"] = { "type" => "enabled" }
    else
      request_body["temperature"] = 0.3
    end

    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Cohere request body: #{request_body.inspect}")
      end
    end

    response = make_http_request(uri, request_body, {
      "Authorization" => "Bearer #{api_key}",
      "Content-Type" => "application/json"
    })

    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Cohere response: #{response&.slice(0, 500) || 'nil'}")
      end
    end

    return nil unless response

    data = JSON.parse(response)

    # For reasoning models, content array may have thinking first, then text
    # Find the text content item
    content_array = data.dig("message", "content")
    result = nil
    if content_array.is_a?(Array)
      text_item = content_array.find { |item| item["type"] == "text" }
      result = text_item["text"] if text_item
    end

    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Cohere content types: #{content_array&.map { |c| c['type'] }&.inspect}")
        log.puts("[#{Time.now}] [ContextExtractor] Cohere parsed result: #{result&.slice(0, 200) || 'nil'}")
      end
    end

    result
  rescue StandardError => e
    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Cohere API error: #{e.class}: #{e.message}")
      end
    end
    nil
  end

  # Call Ollama API (local, no API key required)
  def call_ollama_api(model, system_message)
    uri = URI.parse(API_ENDPOINTS["ollama"])

    request_body = {
      "model" => model,
      "messages" => [
        { "role" => "system", "content" => system_message },
        { "role" => "user", "content" => "Extract context and return JSON only." }
      ],
      "stream" => false,
      "options" => {
        "temperature" => 0.3
      }
    }

    # Ollama uses HTTP (local), not HTTPS
    response = make_http_request_local(uri, request_body, {
      "Content-Type" => "application/json"
    })

    return nil unless response

    data = JSON.parse(response)
    data.dig("message", "content")
  rescue StandardError => e
    puts "[ContextExtractor] Ollama API error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Make HTTP request with timeout (HTTPS)
  def make_http_request(uri, body, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |key, value| request[key] = value }
    request.body = body.to_json

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      response.body
    else
      puts "[ContextExtractor] HTTP error #{response.code}: #{response.body[0..200]}" if CONFIG && CONFIG["EXTRA_LOGGING"]
      nil
    end
  rescue StandardError => e
    puts "[ContextExtractor] HTTP request error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Make HTTP request with timeout (HTTP, no SSL - for local services like Ollama)
  def make_http_request_local(uri, body, headers)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = false
    http.open_timeout = 10
    http.read_timeout = 60  # Longer timeout for local models

    request = Net::HTTP::Post.new(uri.request_uri)
    headers.each { |key, value| request[key] = value }
    request.body = body.to_json

    response = http.request(request)

    if response.code.to_i >= 200 && response.code.to_i < 300
      response.body
    else
      puts "[ContextExtractor] Local HTTP error #{response.code}: #{response.body[0..200]}" if CONFIG && CONFIG["EXTRA_LOGGING"]
      nil
    end
  rescue StandardError => e
    puts "[ContextExtractor] Local HTTP request error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Get API key for provider
  def get_api_key_for_provider(provider)
    return nil unless defined?(CONFIG)

    key = case provider.to_s.downcase
    when "openai" then CONFIG["OPENAI_API_KEY"]
    when "anthropic" then CONFIG["ANTHROPIC_API_KEY"]
    when "gemini" then CONFIG["GEMINI_API_KEY"]
    when "xai" then CONFIG["XAI_API_KEY"]
    when "mistral" then CONFIG["MISTRAL_API_KEY"]
    when "cohere" then CONFIG["COHERE_API_KEY"]
    when "deepseek" then CONFIG["DEEPSEEK_API_KEY"]
    else nil
    end

    key&.to_s&.strip&.empty? ? nil : key
  end

  # Get fallback model for Ollama when no default is configured
  def get_ollama_fallback_model
    if defined?(OllamaHelper) && OllamaHelper.respond_to?(:list_models)
      models = OllamaHelper.list_models
      models&.first
    else
      # Fallback to a common default
      "llama3.2:3b"
    end
  rescue StandardError => e
    puts "[ContextExtractor] Error getting Ollama models: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Process context extraction after a response and broadcast to sidebar
  # @param session [Hash] The session information
  # @param user_message [String] The user's message
  # @param assistant_response [String] The assistant's response
  # @param provider [String] The AI provider
  # @param session_id [String] WebSocket session ID for broadcasting
  # @param schema [Hash] The context schema defining fields to extract (optional)
  def process_and_broadcast_context(session, user_message, assistant_response, provider, session_id, schema = nil)
    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] process_and_broadcast_context called")
        log.puts("[#{Time.now}] [ContextExtractor]   provider=#{provider}, session_id=#{session_id ? 'present' : 'nil'}")
      end
    end

    if session_id.nil?
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] EARLY RETURN: session_id is nil")
        end
      end
      return
    end

    effective_schema = schema || DEFAULT_SCHEMA

    # Extract conversation language from session runtime settings
    language = session.dig(:runtime_settings, :language) || session.dig("runtime_settings", "language")

    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Calling extract_context with language=#{language}")
      end
    end

    context = extract_context(session, user_message, assistant_response, provider, effective_schema, language)

    if context.nil?
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] EARLY RETURN: extract_context returned nil")
        end
      end
      return
    end

    # Check if there's any actual content to broadcast (dynamic field check)
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]
    field_names = fields.map { |f| f[:name] || f["name"] }
    has_content = field_names.any? { |name| context[name]&.any? }

    if !has_content
      if CONFIG && CONFIG["EXTRA_LOGGING"]
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
          log.puts("[#{Time.now}] [ContextExtractor] EARLY RETURN: no content to broadcast")
        end
      end
      return
    end

    # Merge with existing context from session (using dynamic schema)
    merged_context = merge_with_session_context(session, context, effective_schema)

    if CONFIG && CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("[#{Time.now}] [ContextExtractor] Broadcasting context update to session #{session_id}")
      end
    end

    # Broadcast to sidebar via WebSocket (include schema for frontend rendering)
    broadcast_context_update(session_id, merged_context, effective_schema)

    # Also save to session state
    save_context_to_session(session, merged_context)

    log_extraction_success(provider, merged_context, effective_schema) if CONFIG && CONFIG["EXTRA_LOGGING"]
  end

  private

  # Normalize provider name
  def normalize_provider(provider)
    return "openai" if provider.nil? || provider.empty?

    case provider.to_s.downcase
    when /anthropic|claude/
      "anthropic"
    when /gemini|google/
      "gemini"
    when /grok|xai/
      "xai"
    else
      provider.to_s.downcase
    end
  end

  # Parse JSON from LLM response (handles markdown code blocks)
  # @param text [String] The raw response text
  # @param schema [Hash] The context schema defining expected fields
  def parse_context_json(text, schema = nil)
    # Remove markdown code blocks if present
    cleaned = text.gsub(/```json\s*/i, "").gsub(/```\s*/, "").strip

    # Try to find JSON object in the text
    if match = cleaned.match(/\{[^{}]*\}/m)
      cleaned = match[0]
    end

    parsed = JSON.parse(cleaned)

    # Get field names from schema
    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    # Build result with all schema fields
    result = {}
    fields.each do |field|
      name = field[:name] || field["name"]
      result[name] = Array(parsed[name]).map(&:to_s).reject(&:empty?)
    end

    result
  rescue JSON::ParserError => e
    puts "[ContextExtractor] JSON parse error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    nil
  end

  # Check if two text items are similar (one contains the other or are variations)
  # @param text1 [String] First text
  # @param text2 [String] Second text
  # @return [Boolean] True if items are similar variations
  def similar_items?(text1, text2)
    return true if text1 == text2

    t1 = text1.to_s.strip
    t2 = text2.to_s.strip

    return false if t1.empty? || t2.empty?

    # Check if one contains the other (handles "かんたろう" vs "かんたろうさん")
    return true if t1.include?(t2) || t2.include?(t1)

    # Check for common Japanese honorific variations
    # Remove common suffixes and compare
    stripped1 = t1.gsub(/[さんくんちゃん様氏]$/, "")
    stripped2 = t2.gsub(/[さんくんちゃん様氏]$/, "")
    return true if stripped1 == stripped2 && !stripped1.empty?

    false
  end

  # Find if a new item is similar to any existing item
  # @param new_text [String] The new text to check
  # @param existing_items [Array] Existing items to compare against
  # @return [Hash, nil] The similar existing item, or nil if none found
  def find_similar_existing(new_text, existing_items)
    existing_items.find do |item|
      existing_text = item.is_a?(Hash) ? item["text"] : item.to_s
      similar_items?(new_text, existing_text)
    end
  end

  # Merge new context with existing session context
  # @param session [Hash] The session
  # @param new_context [Hash] The new extracted context
  # @param schema [Hash] The context schema defining expected fields
  def merge_with_session_context(session, new_context, schema = nil)
    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    # Build empty defaults based on schema
    defaults = { "_turn_count" => 0 }
    fields.each do |field|
      name = field[:name] || field["name"]
      defaults[name] = []
    end

    existing = get_session_context(session) || defaults

    # Increment turn count
    current_turn = (existing["_turn_count"] || 0) + 1

    # Merge each field with turn information
    result = { "_turn_count" => current_turn }
    fields.each do |field|
      name = field[:name] || field["name"]
      existing_items = existing[name] || []

      # Convert new items to turn-aware format
      new_items = (new_context[name] || []).map do |item|
        if item.is_a?(Hash) && item["text"]
          item  # Already in new format
        else
          { "text" => item.to_s, "turn" => current_turn }
        end
      end

      # Normalize existing items to new format if needed
      normalized_existing = existing_items.map do |item|
        if item.is_a?(Hash) && item["text"]
          item
        else
          { "text" => item.to_s, "turn" => item.is_a?(Hash) ? (item["turn"] || 1) : 1 }
        end
      end

      # Merge with existing items (avoid duplicates and similar variations)
      unique_new_items = []
      new_items.each do |new_item|
        new_text = new_item["text"]
        similar = find_similar_existing(new_text, normalized_existing + unique_new_items)

        if similar.nil?
          # No similar item found, add as new
          unique_new_items << new_item
        else
          # Found similar item - if new one is longer/more complete, replace
          similar_text = similar["text"]
          if new_text.length > similar_text.length
            # Replace the shorter version with the longer one
            if normalized_existing.include?(similar)
              normalized_existing.delete(similar)
              normalized_existing << { "text" => new_text, "turn" => similar["turn"] }
            elsif unique_new_items.include?(similar)
              unique_new_items.delete(similar)
              unique_new_items << new_item
            end
          end
          # Otherwise keep the existing longer version
        end
      end

      result[name] = normalized_existing + unique_new_items
    end

    result
  end

  # Get existing context from session
  def get_session_context(session)
    return nil unless session

    state = session[:monadic_state] || session["monadic_state"]
    return nil unless state

    state[:conversation_context] || state["conversation_context"]
  end

  # Save context to session state
  def save_context_to_session(session, context)
    return unless session

    session[:monadic_state] ||= {}
    session[:monadic_state][:conversation_context] = context
  end

  # Broadcast context update via WebSocket
  # @param session_id [String] The WebSocket session ID
  # @param context [Hash] The context data
  # @param schema [Hash] The context schema for frontend rendering
  def broadcast_context_update(session_id, context, schema = nil)
    effective_schema = schema || DEFAULT_SCHEMA

    message = {
      "type" => "context_update",
      "context" => context,
      "schema" => effective_schema,
      "timestamp" => Time.now.to_f
    }

    if defined?(WebSocketHelper) && WebSocketHelper.respond_to?(:send_to_session)
      WebSocketHelper.send_to_session(message.to_json, session_id)
      puts "[ContextExtractor] Sent context_update to session #{session_id}" if CONFIG && CONFIG["EXTRA_LOGGING"]
    else
      puts "[ContextExtractor] WebSocketHelper not available" if CONFIG && CONFIG["EXTRA_LOGGING"]
    end
  rescue StandardError => e
    puts "[ContextExtractor] Broadcast error: #{e.message}" if CONFIG && CONFIG["EXTRA_LOGGING"]
  end

  # Remove items associated with a specific turn from context
  # @param context [Hash] The current context
  # @param turn_to_remove [Integer] The turn number to remove
  # @param schema [Hash] The context schema
  # @return [Hash] Updated context with items from that turn removed
  def remove_turn_from_context(context, turn_to_remove, schema = nil)
    return context unless context && turn_to_remove

    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    result = { "_turn_count" => context["_turn_count"] || 0 }

    fields.each do |field|
      name = field[:name] || field["name"]
      items = context[name] || []

      # Filter out items from the specified turn
      result[name] = items.reject do |item|
        item_turn = item.is_a?(Hash) ? (item["turn"] || 1) : 1
        item_turn == turn_to_remove
      end
    end

    result
  end

  # Remap turn numbers after a deletion (decrement turns greater than deleted turn)
  # @param context [Hash] The current context
  # @param deleted_turn [Integer] The turn that was deleted
  # @param schema [Hash] The context schema
  # @return [Hash] Updated context with remapped turn numbers
  def remap_turns_after_deletion(context, deleted_turn, schema = nil)
    return context unless context && deleted_turn

    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    # Decrement turn count
    new_turn_count = [(context["_turn_count"] || 0) - 1, 0].max
    result = { "_turn_count" => new_turn_count }

    fields.each do |field|
      name = field[:name] || field["name"]
      items = context[name] || []

      # Remap turn numbers
      result[name] = items.map do |item|
        if item.is_a?(Hash)
          item_turn = item["turn"] || 1
          if item_turn > deleted_turn
            item.merge("turn" => item_turn - 1)
          else
            item
          end
        else
          item
        end
      end
    end

    result
  end

  # Handle context update when a message is deleted
  # @param session [Hash] The session
  # @param deleted_turn [Integer] The turn that was deleted (nil if not an assistant message)
  # @param schema [Hash] The context schema
  # @param session_id [String] WebSocket session ID for broadcasting
  def handle_message_deletion(session, deleted_turn, schema = nil, session_id = nil)
    return unless session && deleted_turn

    context = get_session_context(session)
    return unless context

    effective_schema = schema || DEFAULT_SCHEMA

    # Remove items from the deleted turn
    updated_context = remove_turn_from_context(context, deleted_turn, effective_schema)

    # Remap subsequent turn numbers
    updated_context = remap_turns_after_deletion(updated_context, deleted_turn, effective_schema)

    # Save and broadcast
    save_context_to_session(session, updated_context)

    if session_id
      broadcast_context_update(session_id, updated_context, effective_schema)
    end

    puts "[ContextExtractor] Handled deletion of turn #{deleted_turn}" if CONFIG && CONFIG["EXTRA_LOGGING"]
  end

  # Handle context update when multiple messages are deleted (e.g., "delete this and below")
  # @param session [Hash] The session
  # @param starting_turn [Integer] The first turn to delete (all turns >= this are removed)
  # @param schema [Hash] The context schema
  # @param session_id [String] WebSocket session ID for broadcasting
  def handle_bulk_deletion(session, starting_turn, schema = nil, session_id = nil)
    return unless session && starting_turn

    context = get_session_context(session)
    return unless context

    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    # Keep only items with turn < starting_turn
    result = { "_turn_count" => [starting_turn - 1, 0].max }

    fields.each do |field|
      name = field[:name] || field["name"]
      items = context[name] || []

      result[name] = items.select do |item|
        item_turn = item.is_a?(Hash) ? (item["turn"] || 1) : 1
        item_turn < starting_turn
      end
    end

    # Save and broadcast
    save_context_to_session(session, result)

    if session_id
      broadcast_context_update(session_id, result, effective_schema)
    end

    puts "[ContextExtractor] Handled bulk deletion from turn #{starting_turn}" if CONFIG && CONFIG["EXTRA_LOGGING"]
  end

  # Mark items from a specific turn as edited and re-extract context
  # @param session [Hash] The session
  # @param turn [Integer] The turn that was edited
  # @param user_message [String] The user message for this turn
  # @param assistant_response [String] The assistant response for this turn
  # @param provider [String] The AI provider
  # @param schema [Hash] The context schema
  # @param session_id [String] WebSocket session ID for broadcasting
  # @param language [String] The conversation language
  def handle_message_edit(session, turn, user_message, assistant_response, provider, schema = nil, session_id = nil, language = nil)
    return unless session && turn && user_message && assistant_response

    context = get_session_context(session)
    return unless context

    effective_schema = schema || DEFAULT_SCHEMA

    # First, remove existing items from this turn
    updated_context = remove_turn_from_context(context, turn, effective_schema)

    # Re-extract context for this turn
    new_context = extract_context(session, user_message, assistant_response, provider, effective_schema, language)

    if new_context
      fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

      fields.each do |field|
        name = field[:name] || field["name"]
        new_items = new_context[name] || []

        # Add new items with turn number and edited flag
        new_items_with_meta = new_items.map do |item|
          text = item.is_a?(Hash) ? item["text"] : item.to_s
          { "text" => text, "turn" => turn, "edited" => true }
        end

        updated_context[name] = (updated_context[name] || []) + new_items_with_meta
      end
    end

    # Save and broadcast
    save_context_to_session(session, updated_context)

    if session_id
      broadcast_context_update(session_id, updated_context, effective_schema)
    end

    puts "[ContextExtractor] Handled edit of turn #{turn}" if CONFIG && CONFIG["EXTRA_LOGGING"]
  end

  # Logging helpers
  def log_extraction_error(provider, model, error)
    return unless CONFIG && CONFIG["EXTRA_LOGGING"]
    puts "[ContextExtractor] Error with #{provider}/#{model}: #{error.message}"
  end

  def log_extraction_success(provider, context, schema = nil)
    effective_schema = schema || DEFAULT_SCHEMA
    fields = effective_schema[:fields] || effective_schema["fields"] || DEFAULT_SCHEMA[:fields]

    field_counts = fields.map do |field|
      name = field[:name] || field["name"]
      "#{name}=#{(context[name] || []).length}"
    end.join(", ")

    puts "[ContextExtractor] Extracted: #{field_counts}"
  end
end
