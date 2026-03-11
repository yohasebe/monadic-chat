#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"
require "cgi"
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/language_config"
require_relative "../../utils/model_spec"
require_relative "../../utils/system_prompt_injector"
require_relative "../base_vendor_helper"
require_relative "../../monadic_performance"
require_relative "../../utils/system_defaults"
require_relative "../../utils/ssl_configuration"
require_relative "../../utils/extra_logger"

if defined?(Monadic::Utils::SSLConfiguration)
  Monadic::Utils::SSLConfiguration.configure!
end

# GeminiHelper Module - Interface for Google's Gemini AI Models
#
# GEMINI MODEL VERSIONS:
#
# Gemini 3.1 (gemini-3.1-pro-preview, gemini-3.1-pro-preview-customtools):
#   - Latest model optimized for software engineering and tool usage
#   - customtools variant prioritizes custom tools over built-in tools
#
# Gemini 3 (gemini-3-flash-preview):
#   - Full support for monadic mode + function calling simultaneously
#   - No special workarounds required
#
# Gemini 2.5 (gemini-2.5-flash, gemini-2.5-pro) - Legacy Support:
#   - Has limitation: cannot support function calling and structured JSON output simultaneously
#   - Workaround code is preserved below for backward compatibility
#   - For function calling: uses `reasoning_effort: minimal`
#   - For structured JSON (monadic mode): omits reasoning_effort parameter
#
# Tool Management Strategy:
#   - Info-gathering tools (read-only) are separated from action tools
#   - This prevents exhausting tool call limits with read operations
#
module GeminiHelper
  include BaseVendorHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  # Use v1beta to support newer Gemini 3 models
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
  define_timeouts "GEMINI", open: 10, read: 600, write: 120

  # Gemini 3 Pro Image Preview via v1 generateContent
  # Supports optional image inputs (up to 14) for editing/conditioning:
  # images: array of { mime_type: "image/png", data: "<base64>" }
  # If images is nil, will fall back to images attached to the latest user message in session (if provided)
  def generate_image_with_gemini3_preview(prompt:, model: nil, aspect_ratio: nil, image_size: nil, images: nil, session: nil)
    model ||= if defined?(Monadic::Utils::ModelSpec)
                Monadic::Utils::ModelSpec.default_image_model("gemini")
              end
    require 'net/http'
    require 'json'
    require 'base64'

    api_key = CONFIG["GEMINI_API_KEY"]
    return { success: false, error: "GEMINI_API_KEY not configured" }.to_json unless api_key

    shared_folder = Monadic::Utils::Environment.shared_volume
    model_id = IMAGE_GENERATION_MODELS[model] || model

    image_config = {}
    image_config[:aspectRatio] = aspect_ratio if aspect_ratio && !aspect_ratio.empty?
    image_config[:imageSize] = image_size if image_size && !image_size.empty?

    generation_config = {
      responseModalities: ["TEXT", "IMAGE"]
    }
    generation_config[:imageConfig] = image_config unless image_config.empty?

    parts = [{ text: prompt }]

    # Check if user has uploaded new images in session
    has_uploaded_images = false
    if session && session[:messages]
      has_uploaded_images = session[:messages].any? { |msg|
        msg["role"] == "user" && msg["images"] && msg["images"].any?
      }

      Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Checking for user-uploaded images\n  has_uploaded_images: #{has_uploaded_images}" }
    end

    # Auto-attach last generated image (for iterative editing)
    # ONLY if user hasn't uploaded new images (check both images param and session)
    if session && session[:gemini3_last_image] && (images.nil? || images.empty?) && !has_uploaded_images
      image_path = File.join(shared_folder, session[:gemini3_last_image])
      if File.exist?(image_path)
        # Load and encode the last generated image
        image_data = File.binread(image_path)
        image_b64 = Base64.strict_encode64(image_data)

        # Add to images parameter for processing
        # Use format compatible with existing image processing (data URL format)
        images ||= []
        images = [images] unless images.is_a?(Array)
        mime = case File.extname(session[:gemini3_last_image].to_s).downcase
               when ".png" then "image/png"
               when ".jpg", ".jpeg" then "image/jpeg"
               when ".gif" then "image/gif"
               when ".webp" then "image/webp"
               else "image/png"
               end
        data_url = "data:#{mime};base64,#{image_b64}"
        images << {
          "data" => data_url,
          "name" => session[:gemini3_last_image]
        }

        Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Auto-attached last generated image: #{session[:gemini3_last_image]}\n  This makes iterative editing work like 'editing uploaded image'" }

        # Clear after attaching (one-time use)
        session[:gemini3_last_image] = nil
        # Don't clear duplicate flag here - it's managed by process_functions
      else
        Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Last generated image file not found: #{image_path}" }
        # Clear the reference since file doesn't exist
        session[:gemini3_last_image] = nil
      end
    end

    # Normalize image inputs: prefer explicit images param; fallback to session attachments
    inline_images = []
    if images && images.is_a?(Array)
      inline_images = images
      Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Using explicit images param (#{inline_images.size} image(s))" }
    elsif session && session[:messages]
      # Select user messages that have non-empty images array
      user_messages_with_images = session[:messages].select { |msg|
        msg["role"] == "user" && msg["images"] && msg["images"].any?
      }

      Monadic::Utils::ExtraLogger.log {
        lines = ["Gemini3Preview: Session check",
                 "  Total messages: #{session[:messages].size}",
                 "  User messages with NON-EMPTY images: #{user_messages_with_images.size}"]
        session[:messages].each_with_index do |msg, idx|
          img_count = msg["images"]&.size || 0
          has_actual_images = msg["images"]&.any? || false
          lines << "  Message #{idx}: role=#{msg["role"]}, images_count=#{img_count}, has_actual_images=#{has_actual_images}"
        end
        lines.join("\n")
      }

      if user_messages_with_images.any?
        inline_images = user_messages_with_images.last["images"]

        # Debug logging
        Monadic::Utils::ExtraLogger.log {
          lines = ["  Latest message images type: #{inline_images.class}",
                   "  Latest message images value: #{inline_images.inspect[0..200]}"]
          if inline_images && inline_images.respond_to?(:size)
            lines << "  Found #{inline_images.size} image(s) in latest message"
            inline_images.each_with_index do |img, idx|
              img_name = img["name"] || img[:name] || "unnamed"
              data_preview = (img["data"] || img[:data] || "")[0..50]
              lines << "  Image #{idx + 1}: #{img_name} (data: #{data_preview}...)"
            end
          else
            lines << "  inline_images is nil or not an array!"
          end
          lines.join("\n")
        }
      else
        Monadic::Utils::ExtraLogger.log { "  No user messages with images found" }
      end
    end

    # Limit to max 14 images as per API spec
    inline_images.first(14).each do |img|
      next unless img

      # Extract data (may be data URL or raw base64)
      data = img["data"] || img[:data]
      next unless data

      # If data is a data URL (data:image/png;base64,...), extract base64 part
      if data.start_with?("data:image/")
        base64_data = data.split(',').last
        # Extract mime type from data URL if not explicitly provided
        mime = data.split(';').first.split(':').last if data.include?('image/')
      else
        base64_data = data
      end

      # Fallback mime type detection
      mime ||= img["mime_type"] || img[:mime_type] || img["mimeType"] || "image/png"

      parts << {
        inline_data: {
          mime_type: mime,
          data: base64_data
        }
      }
    end

    body = {
      contents: [
        {
          role: "user",
          parts: parts
        }
      ],
      generationConfig: generation_config
    }

    # Debug: Log request details
    Monadic::Utils::ExtraLogger.log {
      lines = ["Gemini3Preview API Request:",
               "  Model: #{model_id}",
               "  Parts count: #{parts.size}"]
      parts.each_with_index do |part, idx|
        if part[:text]
          lines << "  Part #{idx + 1}: text (length: #{part[:text].length})"
        elsif part[:inline_data]
          lines << "  Part #{idx + 1}: image (mime: #{part[:inline_data][:mime_type]}, data length: #{part[:inline_data][:data].length})"
        end
      end
      lines.join("\n")
    }

    endpoints = [
      "https://generativelanguage.googleapis.com/v1beta/models/#{model_id}:generateContent?key=#{api_key}"
    ]
    response = nil

    endpoints.each do |endpoint|
      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
        http.request(request)
      end
      break if response.code == '200'
    end

    if response.code == '200'
      data = JSON.parse(response.body)
      candidate = data.dig("candidates", 0, "content", "parts")&.find do |p|
        (p["inlineData"] && p["inlineData"]["mimeType"]&.start_with?("image/")) ||
        (p["inline_data"] && p["inline_data"]["mime_type"]&.start_with?("image/"))
      end

      if candidate
        inline = candidate["inlineData"] || candidate["inline_data"]
        mime = inline["mimeType"] || inline["mime_type"] || "image/png"
        b64  = inline["data"]
        ext = case mime
              when "image/png" then "png"
              when "image/jpeg", "image/jpg" then "jpg"
              when "image/webp" then "webp"
              else "png"
              end
        filename = "gemini3_image_#{Time.now.to_i}.#{ext}"
        filepath = File.join(shared_folder, filename)
        File.open(filepath, 'wb') { |f| f.write(Base64.decode64(b64)) }

        # Add generated image to session for iterative editing
        if session && session[:messages]
          data_url = "data:#{mime};base64,#{b64}"
          image_data = {
            "title" => filename,
            "data" => data_url
          }

          # Add as a new user message with the generated image
          session[:messages] << {
            "role" => "user",
            "text" => "[Generated image: #{filename}]",
            "images" => [image_data]
          }

          Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Added generated image to session\n  Filename: #{filename}\n  Session now has #{session[:messages].size} messages" }
        end

        return { success: true, filename: filename, model: model, prompt: prompt }.to_json
      end

      return { success: false, error: "No image returned from Gemini image generation" }.to_json
    else
      error_data = JSON.parse(response.body) rescue {}
      error_message = error_data.dig("error", "message") || "API request failed with status #{response.code}"
      return { success: false, error: error_message }.to_json
    end
  rescue StandardError => e
    return { success: false, error: Monadic::Utils::ErrorFormatter.tool_error(
      provider: "Gemini",
      tool_name: "generate_image_with_gemini3_preview",
      message: e.message
    ) }.to_json
  end


  # Image generation model endpoints (separate from chat models)
  # These are specialized APIs not included in the regular model list
  IMAGE_GENERATION_MODELS = {
    "imagen4" => "imagen-4.0-generate-001",
    "imagen4-ultra" => "imagen-4.0-ultra-generate-001",
    "imagen4-fast" => "imagen-4.0-fast-generate-001",
    # Gemini 3.1 Flash Image Preview (v1beta generateContent)
    "gemini-3.1-flash-image-preview" => "gemini-3.1-flash-image-preview",
    "gemini-3-pro-image-preview" => "gemini-3.1-flash-image-preview"  # backward compat
  }.freeze
  IMAGE_GENERATION_MODEL = IMAGE_GENERATION_MODELS["imagen4-fast"]  # Default to fast model
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  
  # URL Context feature for web content retrieval
  # Supports up to 20 URLs per request
  MAX_URL_CONTEXT = 20
  
  # Supported content types for URL context
  URL_CONTEXT_TYPES = {
    text: ["html", "json", "txt", "xml", "css", "js"],
    image: ["png", "jpeg", "jpg", "bmp", "webp"],
    pdf: ["pdf"]
  }.freeze
  
  # URL Context prompt for better search integration
  URL_CONTEXT_PROMPT = <<~TEXT
    When web search is requested, I will analyze web content directly from URLs.
    This allows me to provide accurate, up-to-date information from reliable sources.
    I can process HTML pages, PDFs, images, and other content types directly.
    
    For search queries, I will:
    1. Identify relevant URLs to analyze
    2. Extract and synthesize information from multiple sources
    3. Provide comprehensive answers with proper citations
    
    **Important**: I will use HTML link tags with target="_blank" and rel="noopener noreferrer" 
    attributes to provide links to source URLs.
  TEXT
  
  SAFETY_SETTINGS = [
    {
      category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_HATE_SPEECH",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_HARASSMENT",
      threshold: "BLOCK_ONLY_HIGH"
    },
    {
      category: "HARM_CATEGORY_DANGEROUS_CONTENT",
      threshold: "BLOCK_ONLY_HIGH"
    }
  ]



  attr_reader :models
  attr_reader :cached_models
  
  # ENV key for emergency override (optional legacy override)
  GEMINI_LEGACY_MODE_ENV = "GEMINI_LEGACY_MODE"

  def self.vendor_name
    "Google"
  end

  def self.list_models
    # Return cached models if they exist
    return $MODELS[:gemini] if $MODELS[:gemini]

    api_key = CONFIG["GEMINI_API_KEY"]
    return [] if api_key.nil?

    headers = {
      "Content-Type": "application/json"
    }

    target_uri = "#{API_ENDPOINT}/models?key=#{api_key}"
      http = HTTP.headers(headers)

    begin
      res = http.get(target_uri)

      if res.status.success?
        model_data = JSON.parse(res.body)
        models = []
        model_data["models"].each do |model|
          name = model["name"].split("/").last
          display_name = model["displayName"]
          models << name if name && /Legacy/ !~ display_name
        end
      end

      return [] if !models || models.empty?

      $MODELS[:gemini] = models.filter do |model|
        /(?:embedding|aqa|vision|imagen|learnlm|gemini-1)/ !~ model
      end.reverse

    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  # Method to manually clear the cache if needed
  def clear_models_cache
    $MODELS[:gemini] = nil
  end

  # Internal Web Search Agent for Gemini
  # This method makes a separate Gemini API call with google_search grounding only,
  # allowing web search to be used as a function call alongside other tools.
  # This works around the Gemini 3 limitation where grounding tools cannot be
  # combined with function_declarations in a single API call.
  #
  # @param query [String] The search query
  # @param model [String] The model to use (defaults to gemini-3-flash-preview)
  # @return [Hash] Search results with sources and content
  def gemini_web_search(query:, n: 5)
    # Instance method wrapper for tool calls
    result = GeminiHelper.internal_web_search(query: query)
    if result[:success]
      # Format for consistency with other search tools
      {
        "query" => query,
        "answer" => result[:content],
        "results" => result[:sources].map do |source|
          if source["queries"]
            { "type" => "search_queries", "queries" => source["queries"] }
          else
            { "title" => source["title"], "url" => source["uri"], "content" => "" }
          end
        end,
        "websearch_agent" => "gemini_internal"
      }
    else
      { "error" => result[:error], "query" => query }
    end
  end

  def self.internal_web_search(query:, model: nil)
    model ||= if defined?(Monadic::Utils::ModelSpec)
                Monadic::Utils::ModelSpec.default_chat_model("gemini")
              end
    api_key = CONFIG["GEMINI_API_KEY"]
    return { error: "GEMINI_API_KEY not configured" } if api_key.nil?

    headers = {
      "Content-Type" => "application/json"
    }

    # Build request body with google_search grounding only
    body = {
      "contents" => [
        {
          "role" => "user",
          "parts" => [{ "text" => "Search the web for: #{query}\n\nProvide comprehensive search results with sources." }]
        }
      ],
      "tools" => [{ "google_search" => {} }],
      "generationConfig" => {
        "temperature" => 0.0,
        "maxOutputTokens" => 4096
      }
    }

    target_uri = "#{API_ENDPOINT}/models/#{model}:generateContent?key=#{api_key}"

    begin
      http = HTTP.headers(headers)
                 .timeout(connect: 30, read: 120, write: 60)
      res = http.post(target_uri, json: body)

      if res.status.success?
        response_data = JSON.parse(res.body)

        # Extract text content
        text_content = ""
        grounding_metadata = nil

        if response_data["candidates"]&.first
          candidate = response_data["candidates"].first
          if candidate["content"]&.dig("parts")
            text_content = candidate["content"]["parts"]
                            .select { |p| p["text"] }
                            .map { |p| p["text"] }
                            .join("\n")
          end
          grounding_metadata = candidate["groundingMetadata"]
        end

        # Extract sources from grounding metadata
        sources = []
        if grounding_metadata
          if grounding_metadata["groundingChunks"]
            grounding_metadata["groundingChunks"].each do |chunk|
              if chunk["web"]
                sources << {
                  "title" => chunk["web"]["title"],
                  "uri" => chunk["web"]["uri"]
                }
              end
            end
          end
          if grounding_metadata["webSearchQueries"]
            sources.unshift({ "queries" => grounding_metadata["webSearchQueries"] })
          end
        end

        {
          success: true,
          content: text_content,
          sources: sources,
          query: query
        }
      else
        error_body = JSON.parse(res.body) rescue { "error" => res.body.to_s }
        {
          success: false,
          error: "API Error: #{error_body.dig('error', 'message') || res.status}",
          query: query
        }
      end
    rescue StandardError => e
      {
        success: false,
        error: "Request failed: #{e.message}",
        query: query
      }
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    # Resolve model via SSOT only (no hardcoded fallback)
    model = model.to_s.strip
    model = nil if model.empty?
    model ||= SystemDefaults.get_default_model('gemini')

    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)

    # Get API key
    api_key = CONFIG["GEMINI_API_KEY"]
    return Monadic::Utils::ErrorFormatter.api_key_error(
      provider: "Gemini",
      env_var: "GEMINI_API_KEY"
    ) if api_key.nil?

    # Check if this is a thinking model
    is_thinking_model = false
    thinking_level_config = Monadic::Utils::ModelSpec.get_thinking_level_options(model)
    thinking_level = nil
    
    # New Gemini 3 thinking level parameter
    if thinking_level_config
      thinking_level = options["reasoning_effort"] || options["thinking_level"] || thinking_level_config[:default]
      is_thinking_model = true
      Monadic::Utils::ExtraLogger.log { "GeminiHelper: Detected thinking-level model #{model} with thinking_level=#{thinking_level}" }
    end
    
    # Thinking budget via reasoning_effort (for models with thinking_budget support)
    if !is_thinking_model && (options["reasoning_effort"] || Monadic::Utils::ModelSpec.supports_thinking?(model) || model =~ /2\.5.*preview/i)
      is_thinking_model = true
      Monadic::Utils::ExtraLogger.log {
        msg = "GeminiHelper: Detected thinking model #{model} with reasoning_effort: #{options["reasoning_effort"]}"
        thinking_budget = Monadic::Utils::ModelSpec.get_thinking_budget(model)
        msg += "\n  Model thinking budget: #{thinking_budget.inspect}" if thinking_budget
        msg
      }
    end
    
    # Set headers
    headers = {
      "content-type" => "application/json"
    }

    # Basic request body
    body = {
      "safety_settings" => SAFETY_SETTINGS,
      "generationConfig" => {
        "maxOutputTokens" => options["max_tokens"] || 800
      }
    }
    
    # Only add temperature for non-thinking models
    if !is_thinking_model || thinking_level
      body["generationConfig"]["temperature"] = options["temperature"] || 0.7
    end

    # For thinking models, configure appropriate parameter
    if thinking_level
      body["generationConfig"]["thinking"] = {
        "level" => thinking_level
      }
    elsif is_thinking_model
      # For models with thinking budget (configure via reasoning_effort)
      reasoning_effort = options["reasoning_effort"] || "low"
      user_max_tokens = options["max_tokens"] || 800
      
      # Get thinking budget configuration from ModelSpec
      thinking_budget = Monadic::Utils::ModelSpec.get_thinking_budget(model)
      
      if thinking_budget && thinking_budget["presets"] && thinking_budget["presets"][reasoning_effort]
        # Use preset value if available
        budget_tokens = thinking_budget["presets"][reasoning_effort]
      elsif thinking_budget
        # Fall back to calculated values based on constraints
        case reasoning_effort
        when "none"
          budget_tokens = thinking_budget["can_disable"] ? 0 : thinking_budget["min"]
        when "minimal"
          budget_tokens = thinking_budget["can_disable"] ? 0 : thinking_budget["min"]
        when "low"
          budget_tokens = [(user_max_tokens * 0.2).to_i, 5000].min
          budget_tokens = [budget_tokens, thinking_budget["min"]].max
        when "medium"
          budget_tokens = [(user_max_tokens * 0.6).to_i, 20000].min
          budget_tokens = [budget_tokens, thinking_budget["min"]].max
        when "high"
          budget_tokens = [(user_max_tokens * 0.8).to_i, thinking_budget["max"]].min
          budget_tokens = [budget_tokens, thinking_budget["min"]].max
        else
          # Default to medium-like value
          budget_tokens = [(thinking_budget["max"] * 0.3).to_i, 10000].min
          budget_tokens = [budget_tokens, thinking_budget["min"]].max
        end
      else
        # No thinking budget defined for this model
        budget_tokens = 0
      end
      
      # Set thinking configuration
      body["generationConfig"]["thinkingConfig"] = {
        "thinkingBudget" => budget_tokens,
        "includeThoughts" => false  # Don't include thoughts in the final output
      }
    end
    
    # Format messages for Gemini API
    formatted_messages = []

    # Process messages
    if options["messages"]
        # Normal processing: include full conversation history
        # Look for system message
        system_msg = options["messages"].find { |m| m["role"] == "system" }
        if system_msg
          # Add system as user message (Gemini has no system role)
          formatted_messages << {
            "role" => "user",
            "parts" => [{ "text" => system_msg["content"].to_s }]
          }
        end

      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)

        # Map roles to Gemini format
        gemini_role = msg["role"] == "assistant" ? "model" : "user"
        content = msg["content"] || msg["text"] || ""

        # Add to formatted messages
        formatted_messages << {
          "role" => gemini_role,
          "parts" => [{ "text" => content.to_s }]
        }
      end
    end
    
    # Add messages to body
    body["contents"] = formatted_messages

    # Add tool definitions if provided (for testing tool-calling apps)
    if options["tools"] && options["tools"].any?
      body["tools"] = [{
        "function_declarations" => options["tools"]
      }]
      body["toolConfig"] = {
        "functionCallingConfig" => {
          "mode" => "AUTO"
        }
      }
    end

    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files

    # Set up API endpoint - use v1beta for thinking models, v1alpha for others
    endpoint = is_thinking_model ? "https://generativelanguage.googleapis.com/v1beta" : API_ENDPOINT
    target_uri = "#{endpoint}/models/#{model}:generateContent?key=#{api_key}"
    
    # Debug logging for SecondOpinion
    Monadic::Utils::ExtraLogger.log { "GeminiHelper send_query: Model=#{model}, Endpoint=#{endpoint}\nGeminiHelper send_query: Full URI=#{target_uri.gsub(/key=.*/, 'key=***')}" }
    
    http = HTTP.headers(headers)
    
    # Make request
    response = nil
    
    # Simple retry logic
    begin
      MAX_RETRIES.times do
        response = http.timeout(
          connect: open_timeout,
          write: write_timeout,
          read: read_timeout
        ).post(target_uri, json: body)

        # Break if successful
        break if response && response.status && response.status.success?

        # Wait before retrying
        sleep RETRY_DELAY
      end

      # Check for valid response
      if !response || !response.status
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Gemini",
          message: "No response from API"
        )
      end
      
      # Process successful response
      if response.status.success?
        parsed_response = JSON.parse(response.body)
        
        # Debug logging for second opinion
        Monadic::Utils::ExtraLogger.log_json("GeminiHelper send_query: Full response structure", parsed_response)
        
        # Extract text from standard response format
        if parsed_response["candidates"] && 
           parsed_response["candidates"][0] && 
           parsed_response["candidates"][0]["content"]
          
          content = parsed_response["candidates"][0]["content"]
          
          # 1. Check for parts array structure (Gemini 1.5 style)
          if content["parts"]
            text_parts = []
            function_calls = []

            content["parts"].each do |part|
              # Skip thinking parts for non-streaming response
              next if part["thought"] == true
              # Also skip modelThinking parts
              next if part["modelThinking"]

              # Check for function calls (tool invocations)
              if part["functionCall"]
                function_calls << part["functionCall"]
              # Handle both part["text"] and part itself being a hash with "text" key
              elsif part["text"]
                text_parts << part["text"]
              elsif part.is_a?(Hash) && part.key?("text")
                text_parts << part["text"]
              end
            end

            # If there are function calls, return them as a structured response
            # This allows tests to evaluate whether tool calls are appropriate
            if function_calls.any?
              return {
                text: text_parts.join(" ").strip,
                tool_calls: function_calls
              }
            end

            result = text_parts.join(" ").strip

            # Handle ReAct format output from Gemini 3 models
            # When model outputs {"action": "...", "action_input": "..."}, extract meaningful content
            if result.start_with?("{") && result.end_with?("}")
              begin
                react_json = JSON.parse(result)
                if react_json.is_a?(Hash)
                  # Skip only completely empty JSON objects
                  if react_json.empty?
                    result = ""
                  # Handle ReAct format: extract action_input if it's a displayable string
                  elsif react_json.key?("action") && react_json.key?("action_input")
                    action_input = react_json["action_input"]
                    if action_input.is_a?(String) && !action_input.strip.empty?
                      result = action_input
                    end
                    # If action_input is not a string or is empty, keep original result
                  end
                end
              rescue JSON::ParserError
                # Not valid JSON, continue with original result
              end
            end

            return result unless result.empty?
          end

          # 2. Check for direct text in content (some Gemini versions)
          if content["text"]
            return content["text"]
          end
          
          # 3. For backward compatibility, try accessing a potential text field 
          # that might be nested in another structure
          content.each do |key, value|
            if value.is_a?(Hash) && value["text"]
              return value["text"]
            end
          end
          
          # 4. Handle response functions (for function calling)
          if content["functionResponse"] && content["functionResponse"]["response"]
            return content["functionResponse"]["response"].to_s
          end
        end
        
        # Attempt a last-chance extraction before returning a parsing error
        fallback_text = extract_text_from_response(parsed_response, 0, 5) rescue nil
        return fallback_text if fallback_text && !fallback_text.to_s.strip.empty?

        # Unable to extract text from response - log the structure
        Monadic::Utils::ExtraLogger.log {
          msg = "GeminiHelper send_query ERROR: Unable to extract text. Response structure:\nCandidates: #{parsed_response["candidates"]&.inspect}"
          if parsed_response["candidates"] && parsed_response["candidates"][0]
            msg += "\nFirst candidate: #{parsed_response["candidates"][0].inspect}"
          end
          msg
        }
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "Gemini",
          message: "Unable to extract text from response"
        )
      else
        # Handle error response
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "Unknown error"
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "Gemini",
          message: error_message,
          code: response.status.code
        )
      end
    rescue StandardError => e
      return Monadic::Utils::ErrorFormatter.api_error(
        provider: "Gemini",
        message: e.message
      )
    end
  end
  
  # Enhanced helper method to extract text from complex response structures
  def extract_text_from_response(response, depth=0, max_depth=3)
    return nil if depth > max_depth
    
    # For nil responses
    return nil if response.nil?
    
    # For string responses (direct text)
    return response if response.is_a?(String) && !response.empty?
    
    # Handle different response formats
    if response.is_a?(Hash)
      # Special handling for Gemini response format
      if response["candidates"].is_a?(Array) && !response["candidates"].empty?
        candidate = response["candidates"][0]
        
        # Process candidate structure for text extraction
        
        # Check for content.parts structure (common in Gemini responses)
        if candidate["content"].is_a?(Hash)
          content = candidate["content"]
          
          # 1. Check for parts array structure first (Gemini 1.5)
          if content["parts"].is_a?(Array)
            text_parts = []
            content["parts"].each do |part|
              # Handle both string and hash formats
              if part.is_a?(Hash) && part["text"].is_a?(String)
                text_parts << part["text"]
              elsif part.is_a?(String)
                text_parts << part
              end
            end
            
            return text_parts.join(" ") if text_parts.any?
          end
          
          # 2. Check for direct text in content (some versions)
          return content["text"] if content["text"].is_a?(String)
          
          # 3. Recurse into nested structures looking for text
          content.each do |key, value|
            if value.is_a?(Hash) && value["text"].is_a?(String)
              return value["text"]
            end
          end
          
          # 4. Handle Gemini 2.0 empty content case
          if content["role"] == "model" && (!content["parts"] || content["parts"].empty?) && !content["text"]
            # Special handling for AI User - returning nil here will let the main method handle the error
            return nil
          end
        end
        
        # 5. Check for direct text in candidate
        return candidate["text"] if candidate["text"].is_a?(String)
        
        # 6. Check for content as string
        return candidate["content"] if candidate["content"].is_a?(String)
        
        # Recursively check candidate object 
        result = extract_text_from_response(candidate, depth+1, max_depth)
        return result if result
      end
      
      # Try common text fields with several variations
      ["text", "content", "message", "output", "result", "answer"].each do |key|
        if response[key].is_a?(String) && !response[key].empty?
          return response[key]
        elsif response[key].is_a?(Hash)
          # Look one level deeper for text
          subresult = extract_text_from_response(response[key], depth+1, max_depth)
          return subresult if subresult
        end
      end
      
      # Recursive descent into all nested objects
      response.each_value do |value|
        result = extract_text_from_response(value, depth+1, max_depth)
        return result if result
      end
    elsif response.is_a?(Array)
      # Combine text from array elements if they're all strings
      if response.all? { |item| item.is_a?(String) }
        combined = response.join(" ").strip
        return combined unless combined.empty?
      end
      
      # Otherwise try each array element recursively
      response.each do |item|
        result = extract_text_from_response(item, depth+1, max_depth)
        return result if result
      end
    end
    
    # Nothing found
    # As a last resort, gather any string content from the structure
    collected = []
    gather_strings(response, collected)
    text = collected.join(' ').strip
    return text unless text.empty?
    nil
  end

  # Recursively collect all string leaves from a nested structure
  def gather_strings(obj, out)
    case obj
    when String
      s = obj.strip
      out << s unless s.empty?
    when Array
      obj.each { |e| gather_strings(e, out) }
    when Hash
      obj.each_value { |v| gather_strings(v, out) }
    end
  end

  # Gemini-specific websearch implementation using URL Context
  def websearch_agent(query: "")
    DebugHelper.debug("Gemini websearch_agent called with query: #{query}", category: :web_search, level: :debug)
    
    # For Gemini, we'll return a message indicating that URL Context handles search
    # The actual URL processing happens in the api_request method
    <<~RESPONSE
      I'll search for information about: #{query}
      
      [Note: Gemini uses native URL Context feature for web search. 
       The search is integrated directly into the model's response generation.]
    RESPONSE
  end
  
  # Helper method to process URL context for web search
  def process_url_context(urls)
    return nil unless urls.is_a?(Array) && !urls.empty?
    
    # Limit to maximum allowed URLs
    urls = urls.first(MAX_URL_CONTEXT)
    
    # According to Gemini docs, URLs should be included in the text, not as separate parts
    # The URL context tool will automatically extract and process them
    
    DebugHelper.debug("Gemini URL Context: Processing #{urls.length} URLs", category: :api, level: :debug)
    urls
  end
  
  # Helper method to search for URLs based on query (placeholder for actual search logic)
  def search_urls_for_query(query)
    # This is a simplified version - in production, you might want to:
    # 1. Use a search API to find relevant URLs
    # 2. Parse existing search results from Google
    # 3. Use predefined URL patterns based on query type
    
    # For now, we'll construct Google search URLs as a fallback
    # This allows Gemini to at least attempt to process search-related content
    search_urls = []
    
    # Add Google search URL
    encoded_query = URI.encode_www_form_component(query)
    search_urls << "https://www.google.com/search?q=#{encoded_query}"
    
    # You could add more specialized URLs based on query patterns
    # For example, Wikipedia for general knowledge, news sites for current events, etc.
    
    DebugHelper.debug("Gemini URL Context: Generated search URLs for query: #{query}", category: :api, level: :debug)
    search_urls
  end
  
  # Helper method to determine which tools should be available next for thinking models
  def get_next_allowed_tools(completed_tools)
    # Define the expected sequence for Jupyter operations
    if completed_tools.empty?
      # First, we need to start Jupyter or create a notebook
      ["run_jupyter", "create_jupyter_notebook", "list_jupyter_notebooks"]
    elsif completed_tools.include?("run_jupyter") && !completed_tools.include?("create_jupyter_notebook")
      # After starting Jupyter, create a notebook
      ["create_jupyter_notebook", "list_jupyter_notebooks"]
    elsif completed_tools.include?("create_jupyter_notebook") && !completed_tools.include?("add_jupyter_cells")
      # After creating notebook, add cells
      ["add_jupyter_cells", "get_jupyter_cells_with_results"]
    else
      # Allow all tools if we're past the initial sequence
      nil  # This will allow all tools
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    # Reset call_depth counter and tool_results for each new user turn
    # This allows unlimited user iterations while preventing infinite loops within a single response
    if role == "user"
      session[:call_depth_per_turn] = 0
      session[:parallel_dispatch_called] = nil
      session[:images_injected_this_turn] = Set.new
      # Clear tool_results from previous turn to prevent stale data affecting termination logic
      session[:parameters]["tool_results"] = []
    end

    # Use per-turn counter instead of parameter for tracking
    current_call_depth = session[:call_depth_per_turn] || 0

    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    temperature = obj["temperature"]&.to_f
    
    # Handle max_tokens
    max_tokens = obj["max_tokens"]&.to_i

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Resolve model capabilities (web search, thinking, tools, streaming)
    model_name = obj["model"]
    caps = resolve_gemini_model_capabilities(obj, model_name)
    use_native_websearch = caps[:use_native_websearch]
    thinking_level = caps[:thinking_level]
    reasoning_effort = caps[:reasoning_effort]
    is_thinking_model = caps[:is_thinking_model]
    tool_capable = caps[:tool_capable]
    supports_streaming = caps[:supports_streaming]

    if role != "tool"
      message = obj["message"].to_s

      html = if message != ""
               markdown_to_html(message)
             else
               message
             end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => message,
                  "html" => html,
                  "lang" => detect_language(message),
                  "app_name" => obj["app_name"]
                } }
        res["content"]["images"] = obj["images"] if obj["images"] && obj["images"].is_a?(Array)

        # Check if this user message was already added by websocket.rb (for context extraction)
        # to avoid duplicate consecutive user messages that cause API errors
        existing_msg = session[:messages].find do |m|
          m["role"] == "user" && m["text"] == message
        end

        if existing_msg
          # Update existing message with additional fields instead of adding new one
          existing_msg.merge!(res["content"])
        else
          session[:messages] << res["content"]
        end

        block&.call res
      end
    end

    # After echoing the user message, validate API key and return a clear error if missing
    api_key = CONFIG["GEMINI_API_KEY"]
    unless api_key && !api_key.to_s.strip.empty?
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "Gemini",
        env_var: "GEMINI_API_KEY"
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!" }
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }

    # Special handling for Gemini 3 Pro Image Preview: clear tool call history
    # to prevent orchestration model from seeing previous results and making duplicate calls
    if @clear_orchestration_history
      Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Clearing orchestration history in api_request\n  Original context size: #{context.size}\n  self.class: #{self.class.name}" }

      # Keep system message + last 1 round of tool interaction + current user message
      # This allows iterative workflows (edit/variation) while preventing duplicate tool calls
      first_msg = context.first
      user_indices = context.each_index.select { |i| context[i]&.[]("role") == "user" }

      if user_indices.length >= 2
        keep_from = user_indices[-2]
        context = [first_msg] + context[keep_from..]
      else
        last_user_msg = context.reverse.find { |msg| msg&.[]("role") == "user" }
        context = [first_msg]
        context << last_user_msg if last_user_msg && first_msg != last_user_msg
      end
      context.compact.each { |msg| msg["active"] = true }

      Monadic::Utils::ExtraLogger.log { "  Filtered context size: #{context.size}" }
    end

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json"
    }

    # Build request body (safety settings, generationConfig, thinkingConfig, systemInstruction)
    system_message = context.find { |msg| msg["role"] == "system" }
    non_system_messages = context.select { |msg| msg["role"] != "system" }
    body = build_gemini_request_body(
      obj: obj, model_name: model_name, session: session, context: context,
      temperature: temperature, max_tokens: max_tokens,
      is_thinking_model: is_thinking_model, thinking_level: thinking_level,
      reasoning_effort: reasoning_effort, tool_capable: tool_capable,
      system_message: system_message
    )

    # Build message contents (role translation, image/PDF injection, user message augmentation)
    contents_result = prepare_gemini_message_contents(
      body: body, obj: obj, model_name: model_name, session: session,
      non_system_messages: non_system_messages, &block
    )
    # Early return on media validation errors
    return contents_result if contents_result.is_a?(Array) && contents_result.any? { |r| r.is_a?(Hash) && r["type"] == "error" }
    has_pdf_part = contents_result == :has_pdf

    # Configure tools (app tools, PTD filtering, web search, URL context)
    app_tools = configure_gemini_tools(
      app: app, role: role, body: body, obj: obj, session: session,
      tool_capable: tool_capable, use_native_websearch: use_native_websearch,
      message: (defined?(message) ? message : nil)
    )

    if role == "tool"
      # Add tool results as function responses to continue the conversation
      # Gemini API requires functionResponse format, not plain text
      parts = obj["tool_results"].map { |result|
        result["functionResponse"] ? { "functionResponse" => result["functionResponse"] } : nil
      }.compact

      if parts.any?
        # Add tool results with role "function" (Gemini's expected format for function responses)
        body["contents"] << {
          "role" => "function",
          "parts" => parts
        }
      end

      # Inject screenshot image(s) as user message for vision-capable models
      # Supports multiple images for tiled screenshots
      # Dedup: skip images already injected in this turn to prevent verify→regenerate loops
      if session[:pending_tool_images]&.any?
        injected_set = session[:images_injected_this_turn] ||= Set.new
        new_images = session[:pending_tool_images].reject { |f| injected_set.include?(f) }

        if new_images.any?
          image_parts = new_images.filter_map do |img_filename|
            img = Monadic::Utils::ToolImageUtils.encode_image_for_api(img_filename)
            next unless img

            injected_set << img_filename
            { "inlineData" => { "mimeType" => img[:media_type], "data" => img[:base64_data] } }
          end
          if image_parts.any?
            body["contents"] << {
              "role" => "user",
              "parts" => [
                { "text" => "[Screenshot of the browser after the action above. Use this visual context to continue with your task.]" },
                *image_parts
              ]
            }
          end
        end
        session.delete(:pending_tool_images)
      end

      # For most apps, we want to stop tool calling after processing results
      # to prevent infinite loops. However, some apps may need multiple sequential calls.
      
      # Check if this is a legacy Gemini 2.5 model (for backward compatibility)
      is_legacy_gemini = obj["model"] && obj["model"].include?("2.5")

      # Check if this is a Jupyter app that needs multiple tool calls
      is_jupyter_app = app.to_s.include?("jupyter") ||
                       (session[:parameters]["app_name"] && session[:parameters]["app_name"].to_s.include?("Jupyter"))

      # Check what tools have been called so far
      tool_names = obj["tool_results"].map { |r| r.dig("functionResponse", "name") }.compact

      if is_jupyter_app
        Monadic::Utils::ExtraLogger.log { "[Jupyter Termination Check] role=tool, tool_names=#{tool_names.inspect}" }
      end

      # Gemini 3+ fully supports function calling with monadic mode
      # Gemini 2.5 also supports function calling (with some workarounds)
      if is_jupyter_app
        # Separate information-gathering tools from action tools
        info_tools = ["get_jupyter_cells_with_results", "list_jupyter_notebooks"]
        action_tools = ["create_jupyter_notebook", "run_jupyter", "add_jupyter_cells",
                       "update_jupyter_cell", "delete_jupyter_cell",
                       "execute_and_fix_jupyter_cells", "run_code",
                       "create_and_populate_jupyter_notebook"]  # Combined tool for Gemini/Grok
        
        # Count only action tools (info tools don't count toward limits)
        action_tool_names = tool_names.reject { |name| info_tools.include?(name) }
        
        # Check what types of operations have been performed
        has_notebook_creation = action_tool_names.any? { |name|
          ["create_jupyter_notebook", "run_jupyter", "create_and_populate_jupyter_notebook"].include?(name)
        }
        
        has_cell_operations = action_tool_names.any? { |name|
          ["add_jupyter_cells", "update_jupyter_cell", "delete_jupyter_cell", "create_and_populate_jupyter_notebook"].include?(name)
        }
        
        has_execution = action_tool_names.any? { |name|
          ["execute_and_fix_jupyter_cells", "run_code"].include?(name)
        }
        
        # Count only action tool calls (not info gathering)
        action_tool_count = action_tool_names.length

        # Determine whether to allow more tool calls based on operation flow
        should_stop = false

        # If create_and_populate was used, it's a complete operation - stop immediately
        # This combined tool handles everything in one call, so we're done
        if action_tool_names.include?("create_and_populate_jupyter_notebook")
          should_stop = true
        end

        # If cells were added (either alone or after notebook creation), stop to show results
        # This covers: run_jupyter + create + add_cells, or just add_cells to existing notebook
        if has_cell_operations
          should_stop = true
        end

        # If we've done any execution, stop to show results
        if has_execution
          should_stop = true
        end

        # Stop if we've made too many ACTION calls (info calls don't count)
        # Limit to 3 to prevent infinite loops: typical flow is run_jupyter + create + add_cells
        if action_tool_count >= 3
          should_stop = true
        end

        Monadic::Utils::ExtraLogger.log { "[Jupyter Termination] action_tool_names=#{action_tool_names.inspect}\n[Jupyter Termination] has_cell_operations=#{has_cell_operations}, has_execution=#{has_execution}, action_tool_count=#{action_tool_count}\n[Jupyter Termination] should_stop=#{should_stop}" }

        if should_stop
          # Disable tools completely to force text response
          # Remove both tools and toolConfig to prevent the model from attempting
          # function calls (Gemini 3 Pro may still try with mode: "NONE")
          body.delete("tools")
          body.delete("toolConfig")

          # Disable thinking completely for tool result processing
          # Gemini 3 Pro ignores thinkingBudget reductions, so we must remove it entirely
          # to ensure tokens are available for text output
          if body["generationConfig"] && body["generationConfig"]["thinkingConfig"]
            body["generationConfig"].delete("thinkingConfig")
          end
        else
          # Still need to call more tools
          if app_tools
            if app_tools.is_a?(Array)
              body["tools"] = [{"function_declarations" => app_tools}]
            else
              body["tools"] = [app_tools]
            end
            
            # Always use AUTO mode for Jupyter apps
            # Let the model decide when to call tools
            body["toolConfig"] = {
              "functionCallingConfig" => {
                "mode" => "AUTO"
              }
            }
          end
        end
      else
        # For non-Jupyter apps, keep AUTO to allow follow-up tool calls
      end

      # Force text-only response when call depth indicates forced termination
      # (e.g., after parallel dispatch or verification sets call_depth_per_turn = FORCE_STOP_DEPTH).
      # Without this, Gemini ignores the "Do NOT call any more tools" text instruction
      # and attempts tool calls, which hit MAX_FUNC_CALLS and truncate the response.
      if session[:call_depth_per_turn] && session[:call_depth_per_turn] >= MAX_FUNC_CALLS
        body.delete("tools")
        body.delete("toolConfig")
      end
    end

    # Remove empty function_declarations to avoid API error
    if body["tools"] && body["tools"].is_a?(Array)
      body["tools"].each do |tool|
        if tool["function_declarations"] && tool["function_declarations"].empty?
          body.delete("tools")
          body.delete("toolConfig")
          break
        end
      end
    end
    
    # Add URL Context for web search functionality (SSOT-gated)
    # IMPORTANT: Gemini 3 Flash Preview doesn't support combining grounding tools (url_context, google_search)
    # with function_declarations. Only add url_context if no function_declarations are present.
    has_function_declarations_before_url_context = body["tools"]&.any? { |tool|
      tool.is_a?(Hash) && tool["function_declarations"]&.any?
    }

    if use_native_websearch && role == "user" && !has_function_declarations_before_url_context
      DebugHelper.debug("Gemini: Adding URL Context for web search", category: :api, level: :debug)

      # Add the url_context tool to enable URL retrieval
      if !body["tools"]
        body["tools"] = []
      end

      # Add url_context tool (according to Gemini docs)
      body["tools"] << { "url_context" => {} }
      
      # Extract search query from the latest user message
      latest_message = body["contents"].last
      if latest_message && latest_message["role"] == "user" && latest_message["parts"]
        user_text = latest_message["parts"].find { |p| p["text"] }&.dig("text")
        
        if user_text
          # Check if the message contains a search-like query
          if user_text =~ /search|find|what is|who is|when|where|how|latest|recent|news|information about/i
            # Generate search URLs
            urls = search_urls_for_query(user_text)
            
            if urls && !urls.empty?
              # According to docs, URLs should be included in the text itself
              # Append URLs to the user's message text
              url_text = urls.join("\n")
              existing_text = latest_message["parts"][0]["text"]
              latest_message["parts"][0]["text"] = "#{existing_text}\n\n#{url_text}"
              
              DebugHelper.debug("Gemini: Added #{urls.length} URLs to message text", category: :api, level: :debug)
            end
          end
          
          # Add system instruction for URL Context if not already present
          if !body["systemInstruction"]
            body["systemInstruction"] = {
              "parts" => [
                { "text" => URL_CONTEXT_PROMPT }
              ]
            }
          else
            # Append URL Context prompt to existing system instruction
            existing_text = body["systemInstruction"]["parts"].find { |p| p["text"] }&.dig("text") || ""
            body["systemInstruction"]["parts"] = [
              { "text" => "#{existing_text}\n\n#{URL_CONTEXT_PROMPT}" }
            ]
          end
          
          DebugHelper.debug("Gemini: URL Context enabled with tool", category: :api, level: :debug)
        end
      end
    end
    
    # Execute API call (endpoint selection, HTTP request, retry, error handling)
    Monadic::Utils::ExtraLogger.log { "[api_request] role=#{role}, calling execute_gemini_api_call with model=#{obj["model"]}, contents_count=#{body["contents"]&.length}, tools_count=#{body["tools"]&.length}" }
    execute_gemini_api_call(
      headers: headers, body: body, obj: obj, api_key: api_key,
      is_thinking_model: is_thinking_model, has_pdf_part: has_pdf_part,
      app: app, session: session, call_depth: call_depth, &block
    )
  rescue HTTP::Error, HTTP::TimeoutError, OpenSSL::SSL::SSLError => e
    Monadic::Utils::ExtraLogger.log { "[api_request] HTTP/SSL error caught: #{e.class}: #{e.message}" }
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY * num_retrial
      retry
    else
      handle_gemini_api_error(e, &block)
    end
  rescue StandardError => e
    Monadic::Utils::ExtraLogger.log { "[api_request] StandardError caught: #{e.class}: #{e.message}\n  #{e.backtrace&.first(5)&.join("\n  ")}" }
    handle_gemini_api_error(e, &block)
  end

  # --- Private helper methods extracted from api_request ---

  private

  # Resolve model capabilities: web search, thinking, tools, streaming (SSOT-based)
  def resolve_gemini_model_capabilities(obj, model_name)
    requested_websearch = obj["websearch"] == true || obj["websearch"] == "true"
    spec_supports_websearch = Monadic::Utils::ModelSpec.supports_web_search?(model_name)
    use_native_websearch = requested_websearch && spec_supports_websearch
    unless use_native_websearch
      DebugHelper.debug("Gemini websearch disabled (requested=#{requested_websearch}, supports=#{spec_supports_websearch})", category: :api, level: :info)
    end
    DebugHelper.debug("Gemini websearch requested: #{requested_websearch}, supports_web_search(spec): #{spec_supports_websearch}, enabled: #{use_native_websearch}", category: :api, level: :debug)

    # Handle thinking models based on reasoning_effort or thinking_level
    thinking_level_config = Monadic::Utils::ModelSpec.get_thinking_level_options(model_name)
    thinking_level = nil
    reasoning_effort = obj["reasoning_effort"]
    if thinking_level_config
      thinking_level = reasoning_effort || obj["thinking_level"] || thinking_level_config[:default]
      reasoning_effort = nil  # Avoid mixing thinking_budget and thinking_level
    end
    is_thinking_model = thinking_level_config ? true : (!reasoning_effort.nil? && !reasoning_effort.empty?)

    # Resolve tool capability (SSOT + optional legacy override)
    spec_tool_capable = Monadic::Utils::ModelSpec.get_model_property(model_name, "tool_capability")
    tool_capable = spec_tool_capable.nil? ? true : !!spec_tool_capable
    if ENV[GEMINI_LEGACY_MODE_ENV] == "true"
      tool_capable = true
    end

    # Resolve supports_streaming for audit (default true)
    spec_supports_streaming = Monadic::Utils::ModelSpec.get_model_property(model_name, "supports_streaming")
    supports_streaming = spec_supports_streaming.nil? ? true : !!spec_supports_streaming
    if ENV[GEMINI_LEGACY_MODE_ENV] == "true"
      supports_streaming = true
    end

    {
      use_native_websearch: use_native_websearch,
      thinking_level: thinking_level,
      reasoning_effort: reasoning_effort,
      is_thinking_model: is_thinking_model,
      tool_capable: tool_capable,
      supports_streaming: supports_streaming
    }
  end

  # Build the Gemini API request body (safety settings, generationConfig, thinkingConfig, systemInstruction)
  def build_gemini_request_body(obj:, model_name:, session:, context:, temperature:, max_tokens:,
                                is_thinking_model:, thinking_level:, reasoning_effort:, tool_capable:,
                                system_message:)
    body = {
      safety_settings: SAFETY_SETTINGS
    }

    # Allow tool calling when tools are available
    tools_param = obj["tools"]
    tools_array = case tools_param
                  when Array
                    tools_param
                  when Hash
                    [tools_param]
                  when String
                    begin
                      parsed = JSON.parse(tools_param)
                      parsed.is_a?(Array) ? parsed : [parsed]
                    rescue JSON::ParserError
                      []
                    end
                  else
                    []
                  end

    # Only add tools and toolConfig when function_declarations exist
    if tool_capable && tools_array.respond_to?(:any?) && tools_array.any?
      body["tools"] = tools_array
      body["toolConfig"] = {
        "functionCallingConfig" => { "mode" => "AUTO" }
      }
    end

    if temperature || max_tokens || is_thinking_model
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens

      # Thinking level (Gemini 3)
      if thinking_level
        model_for_budget = model_name || obj["model"]
        thinking_budget = Monadic::Utils::ModelSpec.get_thinking_budget(model_for_budget)
        budget_tokens = nil
        if thinking_budget && thinking_budget["presets"] && thinking_budget["presets"][thinking_level]
          budget_tokens = thinking_budget["presets"][thinking_level]
        else
          budget_tokens = thinking_level == "high" ? 20000 : 8000
        end

        body["generationConfig"]["thinkingConfig"] = {
          "thinkingBudget" => budget_tokens,
          "includeThoughts" => false
        }
      # Thinking budget (for models with thinking_budget support)
      elsif is_thinking_model && reasoning_effort
        model = obj["model"]

        Monadic::Utils::ExtraLogger.log {
          tb = Monadic::Utils::ModelSpec.get_thinking_budget(model)
          "GeminiHelper api_request: Model thinking budget - #{tb.inspect}" if tb
        }

        user_max_tokens = max_tokens || 8192
        thinking_budget = Monadic::Utils::ModelSpec.get_thinking_budget(model)

        if thinking_budget && thinking_budget["presets"] && thinking_budget["presets"][reasoning_effort]
          budget_tokens = thinking_budget["presets"][reasoning_effort]
        elsif thinking_budget
          case reasoning_effort
          when "none"
            budget_tokens = thinking_budget["can_disable"] ? 0 : thinking_budget["min"]
          when "minimal"
            budget_tokens = thinking_budget["can_disable"] ? 0 : thinking_budget["min"]
          when "low"
            budget_tokens = [(user_max_tokens * 0.3).to_i, 10000].min
            budget_tokens = [budget_tokens, thinking_budget["min"]].max
          when "medium"
            budget_tokens = [(user_max_tokens * 0.6).to_i, 20000].min
            budget_tokens = [budget_tokens, thinking_budget["min"]].max
          when "high"
            budget_tokens = [(user_max_tokens * 0.8).to_i, thinking_budget["max"]].min
            budget_tokens = [budget_tokens, thinking_budget["min"]].max
          else
            budget_tokens = [(thinking_budget["max"] * 0.3).to_i, 10000].min
            budget_tokens = [budget_tokens, thinking_budget["min"]].max
          end
        else
          budget_tokens = 0
        end

        body["generationConfig"]["thinkingConfig"] = {
          "thinkingBudget" => budget_tokens,
          "includeThoughts" => false
        }
      end
    end

    # Set systemInstruction if there's a system message
    if system_message
      augmented_system_prompt = Monadic::Utils::SystemPromptInjector.augment(
        base_prompt: system_message["text"],
        session: session,
        options: {
          websearch_enabled: false,  # Gemini handles websearch differently
          reasoning_model: false,
          websearch_prompt: nil,
          system_prompt_suffix: obj["system_prompt_suffix"]
        },
        separator: "\n\n---\n\n"
      )

      body["systemInstruction"] = {
        "parts" => [
          { "text" => augmented_system_prompt }
        ]
      }
    end

    body
  end

  # Build message contents: role translation, user message augmentation, image/PDF injection
  # Returns :has_pdf, :no_pdf, or an error array for early return
  def prepare_gemini_message_contents(body:, obj:, model_name:, session:, non_system_messages:, &block)
    body["contents"] = non_system_messages.compact.map do |msg|
      {
        "role" => translate_role(msg["role"]),
        "parts" => [{ "text" => msg["text"] }]
      }
    end

    has_pdf_part = false

    if body["contents"].last && body["contents"].last["role"] == "user"
      # Use unified system prompt injector for user message augmentation
      body["contents"].last["parts"].each do |part|
        if part["text"]
          augmented_text = Monadic::Utils::SystemPromptInjector.augment_user_message(
            base_message: part["text"],
            session: session,
            options: { prompt_suffix: obj["prompt_suffix"] }
          )
          part["text"] = augmented_text
          break
        end
      end

      # SSOT: vision/pdf capability gates for inline data
      if obj["images"] && obj["images"].is_a?(Array)
        begin
          spec_vision = Monadic::Utils::ModelSpec.get_model_property(model_name, "vision_capability")
          vision_capable = spec_vision.nil? ? true : !!spec_vision

          spec_pdf = Monadic::Utils::ModelSpec.get_model_property(model_name, "supports_pdf")
          pdf_capable = spec_pdf.nil? ? false : !!spec_pdf

          if ENV[GEMINI_LEGACY_MODE_ENV] == "true"
            vision_capable = true
            pdf_capable = true
          end
        rescue StandardError => e
          vision_capable = true
          pdf_capable = false
          DebugHelper.debug("[GEMINI_SSOT] Failed to get capabilities: #{e.message}", category: :api, level: :warn)
        end

        obj["images"].each do |file|
          media_type = file["type"].to_s
          if media_type == "application/pdf"
            unless pdf_capable
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Gemini", message: "This model does not support PDF input.", code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end
            max_pdf_size_mb = ENV['GEMINI_MAX_INLINE_PDF_MB']&.to_i || 20
            base64_data = file["data"].include?(",") ? file["data"].split(",")[1] : file["data"]

            estimated_size_mb = (base64_data.length * 0.75 / 1024.0 / 1024.0).round(2)
            if estimated_size_mb > max_pdf_size_mb
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Gemini",
                message: "PDF file too large (#{estimated_size_mb}MB). Maximum size is #{max_pdf_size_mb}MB. Please use URL Context or compress the file.",
                code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end

            pdf_part = {
              "inlineData" => { "mimeType" => "application/pdf", "data" => base64_data }
            }
            body["contents"].last["parts"].unshift(pdf_part)
            has_pdf_part = true
          elsif media_type.start_with?("image/")
            unless vision_capable
              formatted_error = Monadic::Utils::ErrorFormatter.api_error(
                provider: "Gemini", message: "This model does not support image input (vision).", code: 400
              )
              res = { "type" => "error", "content" => formatted_error }
              block&.call res
              return [res]
            end
            body["contents"].last["parts"] << {
              "inlineData" => {
                "mimeType" => media_type,
                "data" => file["data"].split(",")[1]
              }
            }
          else
            formatted_error = Monadic::Utils::ErrorFormatter.api_error(
              provider: "Gemini", message: "Unsupported media type: #{media_type}", code: 400
            )
            res = { "type" => "error", "content" => formatted_error }
            block&.call res
            return [res]
          end
        end
      end
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["contents"].empty? && body["systemInstruction"]
      body["contents"] << {
        "role" => "user",
        "parts" => [{ "text" => "Hello" }]
      }
    end

    has_pdf_part ? :has_pdf : :no_pdf
  end

  # Configure tools: app tools collection, PTD filtering, web search tool, URL context
  # Returns the resolved app_tools for use in tool result processing
  def configure_gemini_tools(app:, role:, body:, obj:, session:, tool_capable:, use_native_websearch:, message: nil)
    app_settings = APPS[app]&.settings
    app_tools = app_settings && (app_settings[:tools] || app_settings["tools"]) ? (app_settings[:tools] || app_settings["tools"]) : []

    raw_function_tools =
      if app_tools.is_a?(Hash) && app_tools["function_declarations"]
        app_tools["function_declarations"]
      elsif app_tools.is_a?(Array)
        app_tools
      else
        []
      end

    # Ensure Jupyter apps have basic tool declarations even if missing
    if app.to_s.include?("jupyter") && raw_function_tools.empty?
      raw_function_tools = [
        { "name" => "run_jupyter" },
        { "name" => "create_jupyter_notebook" },
        { "name" => "add_jupyter_cells" },
        { "name" => "get_jupyter_cells_with_results" }
      ]
    end

    progressive_settings = app_settings && (app_settings[:progressive_tools] || app_settings["progressive_tools"])
    progressive_enabled = !!progressive_settings

    filtered_function_tools = raw_function_tools
    if app_settings
      begin
        filtered_function_tools = Monadic::Utils::ProgressiveToolManager.visible_tools(
          app_name: app,
          session: session,
          app_settings: app_settings,
          default_tools: raw_function_tools
        )
      rescue StandardError => e
        DebugHelper.debug("Gemini: Progressive tool filtering skipped due to #{e.message}", category: :api, level: :warning)
        filtered_function_tools = raw_function_tools
      end
    end

    # Re-wrap tools using original structure expectations
    if app_tools.is_a?(Hash) && app_tools["function_declarations"]
      app_tools = { "function_declarations" => filtered_function_tools }
    else
      app_tools = filtered_function_tools
    end

    # NOTE: google_search is a Gemini API grounding feature, NOT a PTD-managed tool.
    google_search_allowed = use_native_websearch

    # Skip tool setup if we're processing tool results
    if role != "tool"
      DebugHelper.debug("Gemini app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
      DebugHelper.debug("Gemini app_tools: #{app_tools.inspect}", category: :api, level: :debug)
      DebugHelper.debug("Gemini app_tools.empty?: #{app_tools.empty?}", category: :api, level: :debug)
      DebugHelper.debug("Gemini websearch requested=#{use_native_websearch}, allowed=#{google_search_allowed}", category: :api, level: :debug)

      # Check if app_tools has actual function declarations
      has_function_declarations = false
      if app_tools
        if app_tools.is_a?(Hash) && app_tools["function_declarations"]
          has_function_declarations = !app_tools["function_declarations"].empty?
        elsif app_tools.is_a?(Array)
          has_function_declarations = !app_tools.empty?
        end
      end

      if has_function_declarations && google_search_allowed
        # Gemini 3 Flash Preview doesn't support combining google_search grounding with function_declarations
        # Solution: Use gemini_web_search as a function declaration instead
        DebugHelper.debug("Gemini: Adding gemini_web_search tool to function declarations (google_search grounding incompatible)", category: :api, level: :debug)

        gemini_web_search_tool = {
          "name" => "gemini_web_search",
          "description" => "Search the web for current information using Google Search. Use this tool when you need to find up-to-date information, verify facts, or research topics. Returns search results with sources.",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "query" => {
                "type" => "string",
                "description" => "The search query to find information on the web"
              }
            },
            "required" => ["query"]
          }
        }

        tools_array = app_tools.is_a?(Array) ? app_tools.dup : (app_tools["function_declarations"] || []).dup

        unless tools_array.any? { |t| t["name"] == "gemini_web_search" }
          tools_array << gemini_web_search_tool
        end

        Monadic::Utils::ExtraLogger.log { "[Gemini Web Search] Added gemini_web_search tool to #{app}\n[Gemini Web Search] Total tools: #{tools_array.length}" }

        body["tools"] = [{"function_declarations" => tools_array}]
        body["toolConfig"] = {
          "functionCallingConfig" => { "mode" => "AUTO" }
        }

      elsif has_function_declarations
        # Only function declarations (no web search)
        if app_tools.is_a?(Array)
          body["tools"] = [{"function_declarations" => app_tools}]
        else
          body["tools"] = [app_tools]
        end

        body["toolConfig"] = {
          "functionCallingConfig" => { "mode" => "AUTO" }
        }
      elsif google_search_allowed
        DebugHelper.debug("Gemini: Google Search enabled for web search", category: :api, level: :debug)
        body["tools"] = [{ "google_search" => {} }]
      else
        DebugHelper.debug("Gemini: No tools or websearch (google_search_allowed=#{google_search_allowed})", category: :api, level: :debug)
        body.delete("tools")
        body.delete("toolConfig")
      end

      # Check if user message contains URLs and add URL Context tool if needed
      if role == "user" && message.is_a?(String) && message != ""
        url_pattern = %r{https?://[^\s<>"{}|\\^\[\]`]+}
        if use_native_websearch && message.match?(url_pattern)
          DebugHelper.debug("Gemini: URLs detected in message, adding URL Context tool", category: :api, level: :debug)

          body["tools"] ||= []
          body["tools"] << { "url_context" => {} }

          urls = message.scan(url_pattern)
          DebugHelper.debug("Gemini: Found URLs: #{urls.inspect}", category: :api, level: :debug)
        end
      end
    end  # end of role != "tool"

    # SSOT: If the model is not tool-capable, keep only google_search/url_context tools
    if body["tools"] && !tool_capable
      body["tools"].select! do |tool|
        tool.is_a?(Hash) && (tool.key?("google_search") || tool.key?("url_context"))
      end
      body.delete("toolConfig")
      body.delete("tools") if body["tools"]&.empty?
    end

    # Debug: Log tools status to extra.log for Jupyter apps
    if app.to_s.include?("Jupyter")
      Monadic::Utils::ExtraLogger.log {
        lines = ["[Gemini Jupyter Debug] role=#{role}, tool_capable=#{tool_capable}",
                 "[Gemini Jupyter Debug] app_tools count: #{app_tools.is_a?(Array) ? app_tools.length : (app_tools.is_a?(Hash) ? app_tools.dig('function_declarations')&.length : 'N/A')}",
                 "[Gemini Jupyter Debug] body has tools: #{body.key?('tools')}, tools count: #{body['tools']&.length || 0}"]
        if body["tools"]
          body["tools"].each_with_index do |tool, idx|
            if tool.is_a?(Hash) && tool["function_declarations"]
              lines << "[Gemini Jupyter Debug] tool[#{idx}] has #{tool['function_declarations'].length} function declarations"
            else
              lines << "[Gemini Jupyter Debug] tool[#{idx}] keys: #{tool.keys rescue 'N/A'}"
            end
          end
        end
        lines.join("\n")
      }
    end

    # Force toolConfig AUTO for tool-capable models on user turns
    has_function_declarations_in_body = body["tools"]&.any? { |tool|
      tool.is_a?(Hash) && tool["function_declarations"]&.any?
    }

    # Debug: Log final tool configuration for Research Assistant
    if app.to_s.include?("Research")
      Monadic::Utils::ExtraLogger.log { "[Gemini Research Debug] Final check: has_function_declarations_in_body=#{has_function_declarations_in_body}\n[Gemini Research Debug] body['tools'] = #{body['tools']&.map { |t| t.keys }.inspect}\n[Gemini Research Debug] body['toolConfig'] = #{body['toolConfig'].inspect}" }
    end

    if role != "tool" && tool_capable && has_function_declarations_in_body
      body["toolConfig"] ||= {}
      body["toolConfig"]["functionCallingConfig"] ||= {}
      body["toolConfig"]["functionCallingConfig"]["mode"] ||= "AUTO"
    end

    app_tools
  end

  # Execute the Gemini API call: endpoint selection, HTTP request with retries, error handling
  def execute_gemini_api_call(headers:, body:, obj:, api_key:, is_thinking_model:, has_pdf_part:,
                              app:, session:, call_depth:, &block)
    # Use v1beta for thinking models or PDF handling, v1alpha for others
    endpoint = (is_thinking_model || has_pdf_part) ? "https://generativelanguage.googleapis.com/v1beta" : API_ENDPOINT
    target_uri = "#{endpoint}/models/#{obj["model"]}:streamGenerateContent?key=#{api_key}"

    http = HTTP.headers(headers)

    # Final safety check: Remove toolConfig if no function_declarations exist
    has_any_function_declarations = body["tools"]&.any? { |tool|
      tool.is_a?(Hash) && tool["function_declarations"]&.any?
    }
    if body["toolConfig"] && !has_any_function_declarations
      Monadic::Utils::ExtraLogger.log { "[Gemini] Removing orphan toolConfig (no function_declarations). tools=#{body["tools"].inspect}" }
      body.delete("toolConfig")
    end

    res = nil

    Monadic::Utils::ExtraLogger.log { "[execute_gemini_api_call] Sending POST to #{target_uri[0..80]}... body contents_count=#{body["contents"]&.length}" }
    MAX_RETRIES.times do |attempt|
      Monadic::Utils::ExtraLogger.log { "[execute_gemini_api_call] Attempt #{attempt + 1}/#{MAX_RETRIES}" } if attempt > 0
      res = http.timeout(connect: open_timeout,
                         write: write_timeout,
                         read: read_timeout).post(target_uri, json: body)
      if res.status.success?
        Monadic::Utils::ExtraLogger.log { "[execute_gemini_api_call] Response status: #{res.status}" }
        break
      end

      Monadic::Utils::ExtraLogger.log { "[execute_gemini_api_call] Non-success status: #{res.status}, retrying..." }
      sleep RETRY_DELAY
    end

    unless res&.status&.success?
      if res.nil?
        formatted_error = Monadic::Utils::ErrorFormatter.api_error(
          provider: "Gemini",
          message: "No response received from API"
        )
        error_res = { "type" => "error", "content" => formatted_error }
        block&.call error_res
        return [error_res]
      end

      error_report = JSON.parse(res.body)

      # Handle both hash and array error formats
      error_message = if error_report.is_a?(Hash)
        error_report.dig("error", "message") || error_report["message"] || "Unknown API error"
      elsif error_report.is_a?(Array)
        error_report.first&.dig("error", "message") || error_report.first&.[]("message") || "Unknown API error (array format)"
      else
        "Unknown API error (unexpected format)"
      end

      formatted_error = Monadic::Utils::ErrorFormatter.api_error(
        provider: "Gemini",
        message: error_message,
        code: res.status.code
      )
      res = { "type" => "error", "content" => formatted_error }
      block&.call res
      return [res]
    end

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
                      call_depth: call_depth, &block)
  end

  # Format and return error responses for API call failures
  def handle_gemini_api_error(error, &block)
    error_message = case error
    when OpenSSL::SSL::SSLError
      Monadic::Utils::ErrorFormatter.network_error(
        provider: "Gemini",
        message: "SSL error: #{error.message}"
      )
    when HTTP::Error, HTTP::TimeoutError
      Monadic::Utils::ErrorFormatter.network_error(
        provider: "Gemini",
        message: "Request timed out",
        timeout: true
      )
    else
      error_details = "Unexpected error: #{error.message}"
      Monadic::Utils::ExtraLogger.log { "[Gemini Error] #{error_details}\nBacktrace: #{error.backtrace[0..5].join("\n")}" }
      Monadic::Utils::ErrorFormatter.api_error(
        provider: "Gemini",
        message: error_details
      )
    end
    res = { "type" => "error", "content" => error_message }
    block&.call res
    [res]
  end

  # --- End of api_request helper methods ---

  public

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    Monadic::Utils::ExtraLogger.log_json("Processing query (Call depth: #{call_depth})", query)
    
    # For media generator apps, we'll need special processing to remove code blocks
    is_media_generator = app.to_s.include?("image_generator") || 
                         app.to_s.include?("video_generator") || 
                         app.to_s.include?("gemini") && 
                         (session[:parameters]["app_name"].to_s.include?("Image Generator") || 
                          session[:parameters]["app_name"].to_s.include?("Video Generator"))

    buffer = String.new
    texts = []
    fragment_sequence = 0  # Sequence number for fragments to ensure ordering
    thinking_parts = []  # Store thinking content
    tool_calls = []
    finish_reason = nil
    @grounding_html = nil  # Store grounding metadata HTML to append to response
    @url_context_html = nil  # Store URL context metadata HTML to append to response
    # Track usage metadata if provider returns it (non-streaming often)
    usage_prompt_tokens = nil
    usage_candidates_tokens = nil
    usage_total_tokens = nil

    # Process streaming response chunks
    res.each do |chunk|
      # Check if we should stop processing due to STOP finish reason
      break if finish_reason == "stop"
      
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      begin
        break if /\Rdata: [DONE]\R/ =~ buffer
      rescue StandardError
        next
      end

      # Skip encoding cleanup - buffer.valid_encoding? check above is sufficient
      # Encoding cleanup with replace: "" can delete valid bytes from incomplete multibyte characters
      # that will become complete when the next chunk arrives
      # buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      # buffer.encode!("UTF-8", "UTF-16")

      if /^\[?(\{\s*"candidates":.*^\})\n/m =~ buffer
        json = Regexp.last_match(1)
        begin
          json_obj = JSON.parse(json)

          Monadic::Utils::ExtraLogger.log_json("Gemini streaming chunk", json_obj)

          # Capture usage metadata if available
          # Gemini may return usageMetadata with keys like promptTokenCount and candidatesTokenCount
          usage_md = json_obj["usageMetadata"] || json_obj["usage_metadata"]
          if usage_md.is_a?(Hash)
            usage_prompt_tokens = usage_md["promptTokenCount"] || usage_md["prompt_tokens"] || usage_prompt_tokens
            usage_candidates_tokens = usage_md["candidatesTokenCount"] || usage_md["completion_tokens"] || usage_candidates_tokens
            # Some variants include totalTokenCount
            usage_total_tokens = usage_md["totalTokenCount"] || (usage_prompt_tokens.to_i + usage_candidates_tokens.to_i if usage_prompt_tokens && usage_candidates_tokens) || usage_total_tokens
          end

          candidates = json_obj["candidates"]

          candidates&.each do |candidate|
            
            # Check for URL Context metadata at candidate level
            if candidate["urlContextMetadata"] &&
               !candidate["urlContextMetadata"].empty? &&
               @url_context_html.nil?
              @url_context_html = build_url_context_html(candidate["urlContextMetadata"])
            end
            
            # Check for grounding metadata at candidate level (skip empty objects)
            if candidate["groundingMetadata"] &&
               !candidate["groundingMetadata"].empty? &&
               @grounding_html.nil?
              @grounding_html = build_grounding_metadata_html(candidate["groundingMetadata"], source: "candidate")
            end

            finish_reason = candidate["finishReason"]
            case finish_reason
            when "MAX_TOKENS"
              # Check if content is empty or contains only thinking signature
              content_check = candidate["content"]
              text_parts = content_check&.dig("parts")&.select { |p| p["text"] && !p["text"].empty? } || []

              if text_parts.empty?
                # Thinking consumed all tokens - return error
                res = { "type" => "error", "content" => "The model's thinking process used all available tokens. Please try again with a simpler request." }
                block&.call res
                return [res]
              end
              finish_reason = "length"
            when "STOP"
              finish_reason = "stop"
              # For thinking models, we should stop processing after receiving STOP
              # to avoid infinite loops
            when "SAFETY"
              finish_reason = "safety"
            when "CITATION"
              finish_reason = "recitation"
            when "MALFORMED_FUNCTION_CALL"
              # Gemini returned a malformed function call
              # With Gemini 3+ models, this should rarely occur
              Monadic::Utils::ExtraLogger.log {
                finish_message = candidate["finishMessage"]
                "[MALFORMED_FUNCTION_CALL]\n  finishMessage (first 300 chars): #{finish_message&.[](0..300)}"
              }

              # If fragments were already streamed, complete the stream
              if fragment_sequence > 0
                res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
                block&.call res
                return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => texts.join } }] }]
              end

              # Return error message
              error_msg = "The model attempted an invalid function call. Please try again or switch to a different model."
              res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
              block&.call res
              return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => error_msg } }] }]
            else
              finish_reason = nil
            end

            content = candidate["content"]

            next if (content.nil? || finish_reason == "recitation" || finish_reason == "safety")

            content["parts"]&.each do |part|
              # Process grounding metadata for web search results (part level)
              if @grounding_html.nil? && (part["grounding_metadata"] || json_obj["groundingMetadata"])
                grounding_data = part["grounding_metadata"] || json_obj["groundingMetadata"]
                @grounding_html = build_grounding_metadata_html(grounding_data, source: "part")
                json_obj.delete("groundingMetadata") if json_obj["groundingMetadata"]
              end
              
              # Check if this part contains thinking content
              if part["thought"] == true && part["text"]
                thinking_fragment = part["text"]
                thinking_parts << thinking_fragment
                
                # Send thinking content as a special type (similar to Claude)
                res = {
                  "type" => "thinking",
                  "content" => thinking_fragment
                }
                block&.call res
                # Skip thinking content - it's internal reasoning, not output
                next
              end
              
              # Also check for modelThinking field (alternative format)
              if part["modelThinking"] && part["modelThinking"]["thought"]
                thinking_fragment = part["modelThinking"]["thought"]
                thinking_parts << thinking_fragment
                
                res = {
                  "type" => "thinking",
                  "content" => thinking_fragment
                }
                block&.call res
                # Skip this part
                next
              end
              
              if part["text"]
                fragment = process_gemini_stream_part(part["text"], session: session, is_media_generator: is_media_generator)
                next if fragment.nil?

                texts << fragment

                if fragment.length > 0
                  res = {
                    "type" => "fragment",
                    "content" => fragment,
                    "sequence" => fragment_sequence,
                    "timestamp" => Time.now.to_f,
                    "is_first" => fragment_sequence == 0
                  }
                  fragment_sequence += 1
                  block&.call res
                end

              elsif part["functionCall"]

                tool_calls << part["functionCall"]
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              end
            end
          end
        rescue JSON::ParserError
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
        buffer = String.new
      end
      
    rescue StandardError => e
      # Log error but continue processing
      STDERR.puts "Error processing JSON data chunk: #{e.message}"
    end


    result = []

    # Generate fallback response when no text was received (but no tool calls either)
    if texts.empty? && !tool_calls.any?
      fallback = generate_gemini_fallback_response(session: session, &block)
      result = fallback[:result]
      finish_reason = fallback[:finish_reason] if fallback[:finish_reason]
    else
      result = texts

      # Post-process ReAct format for Image/Video Generator apps
      # Since streaming sends fragments before we can detect the complete JSON,
      # we need to check the final result and send a replacement if needed
      app_name = session[:parameters]["app_name"].to_s
      if (app_name.include?("ImageGenerator") || app_name.include?("VideoGenerator")) && app_name.include?("Gemini")
        full_text = result.join("").strip
        if full_text.start_with?("{") && full_text.end_with?("}")
          begin
            react_json = JSON.parse(full_text)
            if react_json.is_a?(Hash) && react_json.key?("action") && react_json.key?("action_input")
              action_input = react_json["action_input"]
              if action_input.is_a?(String) && !action_input.strip.empty?
                # Send the extracted content as a replacement fragment
                # Using is_first: true will clear the temp-card content and replace with new content
                res = { "type" => "fragment", "content" => action_input, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
                block&.call res
                # Update result to contain only the extracted content
                result = [action_input]
              end
            end
          rescue JSON::ParserError
            # Not valid JSON, keep original result
          end
        end
      end
    end

    if tool_calls.any?
      context = []

      if result
        context << { "role" => "model", "text" => result.join("") }
      end

      session[:call_depth_per_turn] += 1
      if session[:call_depth_per_turn] > MAX_FUNC_CALLS
        error_content = Monadic::Utils::ErrorFormatter.api_error(
          provider: "Gemini",
          message: "Maximum function call depth exceeded"
        )
        block&.call({ "type" => "error", "content" => error_content })
        block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
        return [{ "type" => "error", "content" => error_content }]
      end

      # Early termination check for Jupyter apps - prevent duplicate tool processing
      app_name = session[:parameters]["app_name"].to_s
      if app_name.include?("Jupyter")
        existing_tool_results = session[:parameters]["tool_results"] || []
        existing_tool_names = existing_tool_results.map { |r| r.dig("functionResponse", "name") }.compact

        # If we've already processed cell operations, skip further tool calls
        jupyter_cell_tools = ["add_jupyter_cells", "update_jupyter_cell", "delete_jupyter_cell"]
        if existing_tool_names.any? { |name| jupyter_cell_tools.include?(name) }
          Monadic::Utils::ExtraLogger.log { "[Jupyter Early Termination] Skipping tool calls - cell operations already completed\n[Jupyter Early Termination] existing_tool_names=#{existing_tool_names.inspect}\n[Jupyter Early Termination] new tool_calls=#{tool_calls.map { |tc| tc['name'] }.inspect}" }
          # Build final content from tool results
          final_content = result.any? ? result.join("") : "Notebook operations completed."

          # Send content to client before returning
          if final_content && !final_content.empty?
            block&.call({ "type" => "fragment", "content" => final_content, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true })
          end
          block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })

          return [{ "choices" => [{ "message" => { "content" => final_content } }] }]
        end
      end

      begin
        # Check if this is a Math Tutor run_code call
        is_math_tutor_code = (session[:parameters]["app_name"].to_s.include?("MathTutor") || 
                              session[:parameters]["display_name"].to_s.include?("Math Tutor")) && 
                             tool_calls.any? { |tc| tc["name"] == "run_code" }
        
        new_results = process_functions(app, session, tool_calls, context, session[:call_depth_per_turn], &block)
        
        # For Math Tutor, inject HTML for generated images
        if is_math_tutor_code && new_results
          # Check if any image files were generated
          result_text = new_results.to_s
          if result_text =~ /File\(s\) generated.*?(\/data\/[^,\s]+\.(?:svg|png|jpg|jpeg|gif))/i
            image_file = $1

            # Inject HTML for the image
            image_html = "\n\n<div class=\"generated_image\">\n  <img src=\"#{image_file}\" />\n</div>"

            # Send the HTML as a supplementary fragment (not first — appends to existing content)
            res = {
              "type" => "fragment",
              "content" => image_html,
              "timestamp" => Time.now.to_f
            }
            block&.call res
          end
        end
      rescue StandardError => e
        new_results = [{ "type" => "error", "content" => Monadic::Utils::ErrorFormatter.api_error(
          provider: "Gemini",
          message: e.message
        ) }]
      end

      if result && new_results
        assemble_gemini_final_result(
          result: result, new_results: new_results,
          tool_calls: tool_calls, session: session, &block
        )
      elsif new_results
        # Notification of function call completion has been removed
        new_results
      elsif result
        # Don't return error messages if they were generated due to initial empty response
        # that was followed by function calls
        if result.is_a?(Array) && result.length == 1 && 
           result[0].to_s.include?("No response was received") && tool_calls.any?
          # Return empty result instead of error message
          [{ "choices" => [{ "message" => { "content" => "" } }] }]
        else
          [{ "choices" => [{ "message" => { "content" => result.join("") } }] }]
        end
      else
        # Return error type instead of a regular message when no response
        [{ "type" => "error", "content" => "No response was received from the model." }]
      end
    elsif result && result.any? && result.join("").strip.length > 0
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res

      # Join the result and check if it needs unwrapping
      final_content = result.join("")
      
      # Check if the entire response is a single Markdown code block and unwrap it
      final_content = unwrap_single_markdown_code_block(final_content)

      # Append URL context metadata HTML if present
      if @url_context_html
        final_content += "\n\n" + @url_context_html
        Monadic::Utils::ExtraLogger.log { "[Gemini] Appended URL context metadata HTML to final response" }
      end
      
      # Append grounding metadata HTML if present
      if @grounding_html
        final_content += "\n\n" + @grounding_html
        Monadic::Utils::ExtraLogger.log { "[Gemini] Appended grounding metadata HTML to final response\n[Gemini] Final content length: #{final_content.length}" }
      else
        Monadic::Utils::ExtraLogger.log { "[Gemini] No grounding HTML to append" }
      end
      
      response_data = {
        "choices" => [
          {
            "finish_reason" => finish_reason,
            "message" => { "content" => final_content }
          }
        ]
      }

      # Attach normalized usage if available
      if usage_prompt_tokens || usage_candidates_tokens || usage_total_tokens
        response_data["usage"] = {
          "input_tokens" => usage_prompt_tokens,
          "output_tokens" => usage_candidates_tokens,
          "total_tokens" => usage_total_tokens
        }.compact
      end
      
      # Don't add thinking content to final response 
      # (it's already been streamed to the user during processing)
      # This prevents duplicate display of thinking content
      # if thinking_parts.any?
      #   response_data["choices"][0]["message"]["thinking"] = thinking_parts.join("\n")
      # end
      
      [response_data]
    else
      # Empty result case - check if Jupyter tools completed successfully
      # This happens when Gemini returns an empty response after tool execution
      is_jupyter_app = app.to_s.include?("jupyter") ||
                       (session[:parameters]["app_name"] && session[:parameters]["app_name"].to_s.include?("Jupyter"))

      # Debug logging for empty result handling
      Monadic::Utils::ExtraLogger.log { "[Gemini Empty Result] app=#{app}, is_jupyter_app=#{is_jupyter_app}\n[Gemini Empty Result] tool_results count: #{session[:parameters]['tool_results']&.length || 0}" }

      if is_jupyter_app
        tool_results = session[:parameters]["tool_results"] || []
        has_successful_jupyter_result = tool_results.any? do |r|
          content = r.dig("functionResponse", "response", "content")
          content.is_a?(String) && (
            content.include?("executed successfully") ||
            content.include?("Notebook") && content.include?("created successfully") ||
            content.include?("cells have been added") || content.include?("Cells added to notebook")
          )
        end

        # Debug logging
        Monadic::Utils::ExtraLogger.log {
          lines = ["[Gemini Empty Result] has_successful_jupyter_result=#{has_successful_jupyter_result}"]
          tool_results.each_with_index do |r, idx|
            content = r.dig("functionResponse", "response", "content")
            lines << "[Gemini Empty Result] tool_result[#{idx}] content preview: #{content.to_s[0..100]}..."
          end
          lines.join("\n")
        }

        if has_successful_jupyter_result
          # Extract notebook info from tool results
          notebook_info = tool_results.find do |r|
            content = r.dig("functionResponse", "response", "content")
            content.is_a?(String) && content.include?(".ipynb")
          end
          notebook_content = notebook_info&.dig("functionResponse", "response", "content") || ""

          # Generate a success message
          success_msg = "Cells added and executed successfully."
          if notebook_content.include?("http://")
            if notebook_content =~ /(http:\/\/[^\s]+\.ipynb)/
              link = $1
              filename = link.split("/").last
              success_msg += "\n\nAccess it at: <a href='#{link}' target='_blank'>#{filename}</a>"
            end
          end

          res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
          block&.call res

          return [{
            "choices" => [
              {
                "finish_reason" => "stop",
                "message" => { "content" => success_msg }
              }
            ]
          }]
        end
      end

      # Default: return empty result for truly empty responses
      # Send DONE to complete the response cycle and prevent UI hang
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" }
      block&.call res

      [{
        "choices" => [
          {
            "finish_reason" => finish_reason || "stop",
            "message" => { "content" => "" }
          }
        ]
      }]
    end
  end

  # --- Private helper methods extracted from process_json_data ---

  private

  # Build HTML for URL context metadata display
  def build_url_context_html(url_context_data)
    Monadic::Utils::ExtraLogger.log { "[Gemini] Found URL Context metadata:\n  - URL metadata count: #{url_context_data["urlMetadata"]&.length}" }

    return nil unless url_context_data["urlMetadata"] && !url_context_data["urlMetadata"].empty?

    url_info = "<div class='url-context-metadata' style='margin: 10px 0; padding: 10px; background: #f0f8ff; border-radius: 5px;'>"
    url_info += "<details style='cursor: pointer;'>"
    url_info += "<summary style='font-weight: bold; color: #666;'>📄 URL Context: #{url_context_data["urlMetadata"].length} URL(s) processed</summary>"
    url_info += "<div style='margin-top: 10px;'>"
    url_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"

    url_context_data["urlMetadata"].each do |url_meta|
      url = url_meta["retrievedUrl"].to_s
      status = url_meta["urlRetrievalStatus"]
      status_emoji = case status
                      when "URL_RETRIEVAL_STATUS_SUCCESS" then "✅"
                      when "URL_RETRIEVAL_STATUS_UNSAFE" then "⚠️"
                      else "❌"
                      end
      safe_url = url.match?(%r{\Ahttps?://}) ? CGI.escapeHTML(url) : CGI.escapeHTML(url)
      display_url = CGI.escapeHTML(url)
      if url.match?(%r{\Ahttps?://})
        url_info += "<li style='margin: 3px 0;'>#{status_emoji} <a href='#{safe_url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{display_url}</a></li>"
      else
        url_info += "<li style='margin: 3px 0;'>#{status_emoji} #{display_url}</li>"
      end
    end

    url_info += "</ul></div></details></div>"

    Monadic::Utils::ExtraLogger.log { "[Gemini] URL Context metadata HTML stored for final response" }

    url_info
  end

  # Build HTML for grounding (web search) metadata display
  def build_grounding_metadata_html(grounding_data, source: "candidate")
    Monadic::Utils::ExtraLogger.log { "[Gemini] Found grounding metadata at #{source} level:\n  - webSearchQueries: #{grounding_data["webSearchQueries"]&.inspect}\n  - groundingChunks count: #{grounding_data["groundingChunks"]&.length}" }

    return nil unless grounding_data["webSearchQueries"] && !grounding_data["webSearchQueries"].empty?

    search_info = "<div class='search-metadata' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>"
    search_info += "<details style='cursor: pointer;'>"
    escaped_queries = grounding_data["webSearchQueries"].map { |q| CGI.escapeHTML(q) }
    search_info += "<summary style='font-weight: bold; color: #666;'>🔍 Web Search: #{escaped_queries.join(", ")}</summary>"

    if grounding_data["groundingChunks"] && !grounding_data["groundingChunks"].empty?
      search_info += "<div style='margin-top: 10px;'>"
      search_info += "<p style='margin: 5px 0; font-weight: bold;'>Sources:</p>"
      search_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"

      grounding_data["groundingChunks"].each_with_index do |chunk, idx|
        if chunk["web"]
          url = chunk["web"]["uri"].to_s
          title = chunk["web"]["title"] || "Source #{idx + 1}"
          title = CGI.escapeHTML(title)
          if url.match?(%r{\Ahttps?://})
            safe_url = CGI.escapeHTML(url)
            search_info += "<li style='margin: 3px 0;'><a href='#{safe_url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{title}</a></li>"
          else
            search_info += "<li style='margin: 3px 0;'>#{title}</li>"
          end
        end
      end

      search_info += "</ul></div>"
    end

    search_info += "</details></div>"

    Monadic::Utils::ExtraLogger.log { "[Gemini] Grounding metadata HTML stored for final response (#{source} level)\n[Gemini] HTML preview: #{search_info[0..200]}..." }

    search_info
  end

  # Process a single text part from the stream: ReAct format handling, code block stripping
  # Returns the processed fragment text, or nil to skip the part
  def process_gemini_stream_part(text, session:, is_media_generator:)
    fragment = text

    # Handle ReAct format output from Gemini 3 models
    stripped_fragment = fragment.strip
    if stripped_fragment.start_with?("{") && stripped_fragment.end_with?("}")
      begin
        react_json = JSON.parse(stripped_fragment)
        if react_json.is_a?(Hash)
          Monadic::Utils::ExtraLogger.log { "Gemini ReAct: keys=#{react_json.keys}, action_input_class=#{react_json["action_input"].class}" }

          # Skip only completely empty JSON objects
          return nil if react_json.empty?

          # Handle ReAct format: extract action_input if it's a displayable string
          if react_json.key?("action") && react_json.key?("action_input")
            action_input = react_json["action_input"]
            if action_input.is_a?(String) && !action_input.strip.empty?
              fragment = action_input
            end
          end
        end
      rescue JSON::ParserError
        # Not valid JSON, continue with original fragment
      end
    end

    # Special handling for Math Tutor FIRST - needs priority
    if session[:parameters]["app_name"].to_s.include?("MathTutor") ||
       session[:parameters]["display_name"].to_s.include?("Math Tutor")
      if fragment =~ /```(?:html)?\s*\n?(<div class="generated_image">.*?<\/div>)\s*\n?```/im
        fragment = fragment.gsub(/```(?:html)?\s*\n?(<div class="generated_image">.*?<\/div>)\s*\n?```/im, '\1')
      end
    # Extract HTML from code blocks for media generator and code interpreter apps
    elsif !session[:parameters]["app_name"].to_s.include?("Jupyter") &&
       (is_media_generator || session[:parameters]["app_name"].to_s.include?("Code Interpreter") ||
        session[:parameters]["app_name"].to_s.include?("Video Generator")) && fragment.include?("```")
      if session[:parameters]["app_name"].to_s.include?("Video Generator")
        if fragment =~ /<div class="(?:prompt|generated_video)">.*?<\/div>/im
          html_pattern = /<div.*?>.*?<\/div>|<p.*?>.*?<\/p>/im
          html_elements = []
          fragment.scan(html_pattern) { |match| html_elements << match }
          fragment = html_elements.join("\n") if html_elements.any?
        else
          content_inside_blocks = []
          fragment.scan(/```(?:html|)\s*(.+?)\s*```/m) { |match| content_inside_blocks << match[0] }
          if content_inside_blocks.any?
            fragment = content_inside_blocks.join("\n\n")
          else
            fragment = fragment.gsub(/```(?:html|\w*)?/, "").gsub(/```/, "")
          end
        end
      elsif fragment =~ /<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im
        html_sections = []
        code_sections = []

        fragment.scan(/<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im) do
          html_sections << $&
        end

        if fragment.match(/```(\w+)?.*?```/m)
          fragment.scan(/```(\w+)?(.*?)```/m) do |lang, code|
            unless code =~ /<div class="generated_(image|video)">.*?<(img|video).*?src="\/data\/.*?\.(?:png|jpg|jpeg|gif|svg|mp4|webm|ogg)".*?>.*?<\/div>/im
              code_sections << "```#{lang}#{code}```"
            end
          end
        end

        if !html_sections.empty? || !code_sections.empty?
          new_fragment = fragment.dup
          new_fragment.gsub!(/```(\w+)?.*?```/m, '')
          html_sections.each { |html| new_fragment.gsub!(html, '') }
          new_fragment = new_fragment.strip
          code_sections.each { |code| new_fragment += "\n\n#{code}" }
          html_sections.each { |html| new_fragment += "\n\n#{html}" }
          fragment = new_fragment.strip
        end
      elsif fragment.include?("```html") && fragment.include?("```")
        if fragment =~ /```html\s*(.*?)\s*```/m
          html_content = $1
          fragment = fragment.gsub(/```html\s*.*?\s*```/m, html_content)
        else
          html_content = fragment.gsub(/```html\s+/, "").gsub(/\s+```/, "")
          fragment = html_content
        end
      elsif fragment.match(/```(\w+)?/)
        if is_media_generator
          fragment = fragment.gsub(/```(\w+)?/, "").gsub(/```/, "")
        end
      end
    end

    fragment
  end

  # Generate fallback response when no text was received from the model
  # Returns a hash with :result (Array) and optionally :finish_reason
  def generate_gemini_fallback_response(session:, &block)
    app_name = session[:parameters]["app_name"].to_s
    if app_name.include?("ImageGenerator") && app_name.include?("Gemini")
      fallback_greeting = "Welcome! I can generate and edit images using Gemini. Describe the image you want, or upload an image to edit it!"
      res = { "type" => "fragment", "content" => fallback_greeting, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
      block&.call res
      { result: [fallback_greeting] }
    elsif app_name.include?("VideoGenerator") && app_name.include?("Gemini")
      fallback_greeting = "Welcome! I can create videos using Google's Veo. Simply describe your video or upload an image to animate!"
      res = { "type" => "fragment", "content" => fallback_greeting, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
      block&.call res
      { result: [fallback_greeting] }
    elsif app_name.include?("JupyterNotebook") && app_name.include?("Gemini")
      Monadic::Utils::ExtraLogger.log { "[DEBUG] texts.empty? fallback: JupyterNotebook Gemini branch entered" }
      tool_results = session[:parameters]["tool_results"] || []
      has_successful_jupyter_result = tool_results.any? do |r|
        content = r.dig("functionResponse", "response", "content")
        content.is_a?(String) && !content.include?("ERRORS DETECTED") && (
          content.include?("executed successfully") ||
          content.include?("Notebook") && content.include?("created successfully") ||
          content.include?("cells have been added") || content.include?("Cells added to notebook")
        )
      end

      if has_successful_jupyter_result
        notebook_info = tool_results.find do |r|
          content = r.dig("functionResponse", "response", "content")
          content.is_a?(String) && content.include?(".ipynb")
        end
        notebook_content = notebook_info&.dig("functionResponse", "response", "content") || ""

        success_msg = "Notebook created and executed successfully."
        if notebook_content =~ /(http:\/\/[^\s]+\.ipynb)/
          link = $1
          filename = link.split("/").last
          success_msg += "\n\nAccess it at: <a href='#{link}' target='_blank'>#{filename}</a>"
        end

        res = { "type" => "fragment", "content" => success_msg, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
        block&.call res
        { result: [success_msg] }
      else
        notebook_error_result = tool_results.find do |r|
          content = r.dig("functionResponse", "response", "content")
          content.is_a?(String) && content.include?("ERRORS DETECTED")
        end

        if notebook_error_result
          error_content = notebook_error_result.dig("functionResponse", "response", "content")
          if error_content =~ /⚠️\s*ERRORS DETECTED.*?(?=\n\nAccess the notebook|$)/m
            error_summary = $&
          else
            error_summary = "Notebook execution errors occurred."
          end
          error_msg = "Errors occurred during notebook execution.\n\n#{error_summary}"
          res = { "type" => "fragment", "content" => error_msg, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
          block&.call res
          { result: [error_msg] }
        else
          fallback_msg = "JupyterLab is ready. Please describe the notebook you'd like to create or the task you want to accomplish."
          res = { "type" => "fragment", "content" => fallback_msg, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
          block&.call res
          { result: [fallback_msg] }
        end
      end
    else
      res = { "type" => "error", "content" => "No response received from model" }
      block&.call res
      { result: [], finish_reason: "error" }
    end
  end

  # Assemble the final result combining initial text with tool call results
  def assemble_gemini_final_result(result:, new_results:, tool_calls:, session:, &block)
    begin
      # More robust handling of different response structures
      if new_results.is_a?(Array) && new_results[0].is_a?(Hash) && new_results[0]["choices"]
        tool_result_content = new_results.dig(0, "choices", 0, "message", "content").to_s.strip
      else
        tool_result_content = new_results.to_s.strip
      end

      # Special handling for Math Tutor run_code results
      if (session[:parameters]["app_name"].to_s.include?("MathTutor") ||
          session[:parameters]["display_name"].to_s.include?("Math Tutor")) &&
         tool_calls.any? { |tc| tc["name"] == "run_code" }
        if tool_result_content =~ /File\(s\) generated.*?(\/data\/[^,\s;]+\.(?:svg|png|jpg|jpeg|gif))/i
          image_file = $1
          tool_result_content += "\n\n<div class=\"generated_image\">\n  <img src=\"#{image_file}\" />\n</div>"
        end
      end

      # Don't add generic content if tool_result_content is empty for video/image generation
      if tool_result_content.empty? && !tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" || tc["name"] == "generate_image_with_gemini" }
        tool_result_content = "[No additional content received from function call]"
      end

      # For Jupyter tools, extract notebook info from session tool_results
      jupyter_tools = %w[
        create_and_populate_jupyter_notebook add_jupyter_cells create_jupyter_notebook
        get_jupyter_cells_with_results delete_jupyter_cell update_jupyter_cell
        insert_jupyter_cells move_jupyter_cell restart_jupyter_kernel run_jupyter
      ]
      is_jupyter_tool = tool_calls.any? { |tc| jupyter_tools.include?(tc["name"]) }

      Monadic::Utils::ExtraLogger.log { "[Jupyter Debug] is_jupyter_tool=#{is_jupyter_tool}, tool_result_content='#{tool_result_content[0..100]}'\n[Jupyter Debug] tool_calls=#{tool_calls.map { |tc| tc['name'] }.inspect}" }

      if is_jupyter_tool && tool_result_content == "[No additional content received from function call]"
        session_tool_results = session[:parameters]["tool_results"] || []

        Monadic::Utils::ExtraLogger.log {
          lines = ["[Jupyter Debug] session_tool_results count=#{session_tool_results.length}"]
          session_tool_results.each_with_index do |r, idx|
            content = r.dig("functionResponse", "response", "content").to_s[0..200]
            lines << "[Jupyter Debug] result[#{idx}]: #{content}"
          end
          lines.join("\n")
        }

        jupyter_result = session_tool_results.reverse.find do |r|
          content = r.dig("functionResponse", "response", "content")
          next false unless content.is_a?(String)
          content.include?(".ipynb") ||
            content.include?("cells have been added") ||
            content.include?("Cells added") ||
            content.include?("JupyterLab") ||
            content.include?("Cell ") ||
            content.start_with?("[{")
        end

        if jupyter_result
          jupyter_content = jupyter_result.dig("functionResponse", "response", "content")

          success_msg = nil
          if jupyter_content.include?("created successfully") || (jupyter_content.include?("Notebook") && jupyter_content.include?("created"))
            success_msg = "Notebook created successfully."
          elsif jupyter_content.include?("cells have been added") || jupyter_content.include?("Cells added")
            success_msg = "Cells added to notebook successfully."
          elsif jupyter_content.include?("deleted successfully")
            success_msg = "Cell deleted successfully."
          elsif jupyter_content.include?("updated successfully")
            success_msg = "Cell updated successfully."
          elsif jupyter_content.include?("JupyterLab is running")
            success_msg = "JupyterLab is running."
          elsif jupyter_content.include?("kernel") && jupyter_content.include?("restart")
            success_msg = "Kernel restarted successfully."
          elsif jupyter_content.start_with?("[{") || jupyter_content.include?('"cell_type"')
            tool_result_content = jupyter_content
            success_msg = nil
          end

          if success_msg
            if jupyter_content =~ /(http:\/\/[^\s]+\.ipynb)/
              link = $1
              filename = link.split("/").last
              success_msg += "\n\nAccess it at: <a href='#{link}' target='_blank'>#{filename}</a>"
            end
            tool_result_content = success_msg
          end
        end
      end

      # Clean up any "No response" messages
      if result.is_a?(Array) && result.length == 1 &&
         result[0].to_s.include?("No response was received")
        result = []
      end

      final_result = result.join("").strip

      # Special handling for video generation
      if tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" }
        video_success = !tool_result_content.include?("Video generation failed") && tool_result_content.include?("saved video")
        if video_success || tool_result_content.include?("Video generation failed") || !tool_result_content.empty?
          final_result = tool_result_content
        end
      # Special handling for image generation
      elsif tool_calls.any? { |tc| tc["name"] == "generate_image_with_gemini" }
        if !tool_result_content.empty?
          final_result = tool_result_content
        elsif final_result.empty?
          final_result = "Image generation function was called but no result was returned."
        end
      else
        # Standard handling for non-media tools
        if !final_result.empty? && !tool_result_content.empty?
          final_result += "\n\n" + tool_result_content
        elsif final_result.empty? && !tool_result_content.empty?
          final_result = tool_result_content
        elsif final_result.empty? && tool_result_content.empty?
          final_result = "Function was called but no content was returned."
        end
      end

      # For Math Tutor, send the HTML image tag directly to frontend if present
      if (session[:parameters]["app_name"].to_s.include?("MathTutor") ||
          session[:parameters]["display_name"].to_s.include?("Math Tutor")) &&
         final_result.include?("<div class=\"generated_image\">")
        if final_result =~ /(<div class="generated_image">.*?<\/div>)/m
          image_html = $1
          res = { "type" => "fragment", "content" => image_html, "timestamp" => Time.now.to_f }
          block&.call res
          final_result = final_result.gsub(/<div class="generated_image">.*?<\/div>/m, '').strip
        end
      end

      [{ "choices" => [{ "message" => { "content" => final_result } }] }]
    rescue StandardError => e
      result_text = result.join("").strip
      result_text = "" if result_text.include?("No response was received")

      if tool_calls.any? { |tc| tc["name"] == "generate_video_with_veo" }
        error_details = e.message.to_s
        if error_details =~ /Successfully saved video to: .*?\/(\d+_\d+_\d+x\d+\.mp4)/ ||
           error_details =~ /(\d{10}_\d+_\d+x\d+\.mp4)/ ||
           error_details =~ /Created placeholder video file at: .*?\/(\d+_\d+_\d+x\d+\.mp4)/
          final_result = error_details
        else
          error_message = "[Error processing video generation results: #{e.message}]"
          final_result = result_text.empty? ? error_message : result_text + "\n\n" + error_message
        end
      else
        error_message = "[Error processing function results: #{e.message}]"
        final_result = result_text.empty? ? error_message : result_text + "\n\n" + error_message
      end

      [{ "choices" => [{ "message" => { "content" => final_result } }] }]
    end
  end

  # --- End of process_json_data helper methods ---

  public

  def process_functions(app, session, tool_calls, context, call_depth, &block)
    return false if tool_calls.empty?

    # Get parameters from the session
    session_params = session[:parameters]

    # Initialize tool_results array in session parameters if it doesn't exist
    session_params["tool_results"] ||= []

    # Note: Duplicate prevention is now handled by clearing orchestration history
    # The @clear_orchestration_history flag in ImageGeneratorGemini3Preview
    # ensures the orchestration model doesn't see previous tool calls

    # Log tool calls for debugging
    Monadic::Utils::ExtraLogger.log {
      lines = ["[DEBUG Tools] Processing #{tool_calls.length} tool calls:"]
      tool_calls.each { |tc| lines << "  - #{tc['name']} with args: #{tc['args'].inspect[0..200]}" }
      lines.join("\n")
    }
    
    # Process each tool call
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]
      block&.call({ "type" => "tool_executing", "content" => function_name })

      begin
        Monadic::Utils::ExtraLogger.log { "[process_functions] Preparing args for #{function_name}" }
        argument_hash = prepare_gemini_tool_arguments(tool_call, app, function_name, session)

        Monadic::Utils::ExtraLogger.log { "[process_functions] Invoking #{function_name} with #{argument_hash.keys.inspect}" }
        function_return = invoke_gemini_tool_function(app, function_name, argument_hash)
        Monadic::Utils::ExtraLogger.log { "[process_functions] #{function_name} returned #{function_return.to_s[0..200]}" }

        send_verification_notification(session, &block) if function_name == "report_verification"

        # Extract TTS text from tool parameters if tts_target is configured
        Monadic::Utils::TtsTextExtractor.extract_tts_text(
          app: app,
          function_name: function_name,
          argument_hash: argument_hash,
          session: session
        )

        # Process the returned content
        if function_return
          content = handle_media_generation_result(function_name, function_return, session)

          # Check for repeated errors before adding to tool results
          if handle_function_error(session, content, function_name, &block)
            # Stop retrying - add result and skip to loop exit
            session_params["tool_results"] << {
              "functionResponse" => {
                "name" => function_name,
                "response" => {
                  "name" => function_name,
                  "content" => content
                }
              },
              "call_depth" => call_depth
            }
            next
          end

          # Add to tool results and debug
          session_params["tool_results"] << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => content
              }
            },
            "call_depth" => call_depth  # Track call_depth to prevent duplicates within same turn
          }

          # Tool result added (debug logging removed)
        end
      rescue StandardError => e
        handle_gemini_tool_execution_error(e, function_name, argument_hash, session_params, &block)
      end
    end

    # For Image/Video Generator apps, skip the recursive api_request after successful generation
    # This prevents the model from seeing the tool result and calling the tool again
    app_name = session[:parameters]["app_name"].to_s
    if @clear_orchestration_history && (app_name.include?("ImageGenerator") || app_name.include?("VideoGenerator"))
      # Check if we have a successful generation result
      last_result = session_params["tool_results"]&.last
      if last_result && last_result["functionResponse"]
        response_content = last_result.dig("functionResponse", "response", "content").to_s

        # Check for media generation success (image or video)
        if response_content.include?('"success":true') || response_content.include?('"success": true')
          begin
            parsed = JSON.parse(response_content)
            if parsed["success"] && parsed["filename"]
              filename = parsed["filename"]
              prompt = parsed["prompt"] || "Media generation"

              # Check if this is a video file
              if filename.to_s.end_with?(".mp4")
                # Send the video HTML directly to the client
                video_html = <<~HTML
                  <div class="prompt" style="margin-bottom: 15px;">
                    <b>Prompt</b>: #{prompt}
                  </div>
                  <div class="generated_video">
                    <video controls width="600">
                      <source src="/data/#{filename}" type="video/mp4" />
                    </video>
                  </div>
                HTML

                res = { "type" => "fragment", "content" => video_html, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
                block&.call res

                # Send DONE message to complete the response
                res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
                block&.call res

                Monadic::Utils::ExtraLogger.log { "Gemini: Sent video HTML directly, skipping recursive api_request\n  Filename: #{filename}" }

                # Return the HTML as the result
                return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => video_html } }] }]
              else
                # Send the image HTML directly to the client
                image_html = <<~HTML
                  <div class="prompt" style="margin-bottom: 15px;">
                    <b>generate</b>: #{prompt}
                  </div>
                  <div class="generated_image">
                    <img src="/data/#{filename}" style="max-width: 100%; border-radius: 8px; border: 1px solid #eee;">
                  </div>
                HTML

                res = { "type" => "fragment", "content" => image_html, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
                block&.call res

                # Send DONE message to complete the response
                res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
                block&.call res

                Monadic::Utils::ExtraLogger.log { "Gemini: Sent image HTML directly, skipping recursive api_request\n  Filename: #{filename}" }

                # Return the HTML as the result
                return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => image_html } }] }]
              end
            end
          rescue JSON::ParserError
            # Continue to normal flow if parsing fails
          end
        end

        # Check for video generation success
        if response_content.include?("Successfully saved video") || response_content.include?(".mp4")
          if response_content =~ /\/data\/([^\s,]+\.mp4)/
            video_filename = $1
            prompt_match = response_content.match(/Original prompt: (.+?)(?:\n|$)/)
            prompt = prompt_match ? prompt_match[1] : "Video generation"

            # Send the video HTML directly to the client
            video_html = <<~HTML
              <div class="prompt" style="margin-bottom: 15px;">
                <b>Prompt</b>: #{prompt}
              </div>
              <div class="generated_video">
                <video controls width="600">
                  <source src="/data/#{video_filename}" type="video/mp4" />
                </video>
              </div>
            HTML

            res = { "type" => "fragment", "content" => video_html, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
            block&.call res

            # Send DONE message to complete the response
            res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
            block&.call res

            Monadic::Utils::ExtraLogger.log { "Gemini: Sent video HTML directly, skipping recursive api_request\n  Filename: #{video_filename}" }

            # Return the HTML as the result
            return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => video_html } }] }]
          end
        end

        # Check for error response from image/video generation tool
        # Prevents unnecessary recursive API call when generation failed
        if response_content.include?('"error"') || response_content.include?('"success":false') || response_content.include?('"success": false')
          begin
            parsed = JSON.parse(response_content)
            error_msg = parsed["error"] || parsed["message"] || "Media generation failed"

            res = { "type" => "fragment", "content" => error_msg, "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
            block&.call res

            res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
            block&.call res

            Monadic::Utils::ExtraLogger.log { "Gemini: Media generation returned error, skipping recursive api_request\n  Error: #{error_msg}" }

            return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => error_msg } }] }]
          rescue JSON::ParserError
            # Continue to normal flow if parsing fails
          end
        end
      end
    end

    # Stop if repeated errors detected
    if should_stop_for_errors?(session)
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      return [{ "choices" => [{ "finish_reason" => "stop", "message" => { "content" => "Repeated errors detected." } }] }]
    end

    # Make the API request with the tool results
    Monadic::Utils::ExtraLogger.log { "[process_functions] Making recursive api_request('tool') with #{session[:parameters]['tool_results']&.length || 0} tool results, call_depth=#{call_depth}" }

    api_request("tool", session, call_depth: call_depth, &block)
  end

  # --- Private helper methods extracted from process_functions ---

  private

  # 3a: Parse, symbolize, and prepare tool arguments from a Gemini tool call
  def prepare_gemini_tool_arguments(tool_call, app, function_name, session)
    # Parse arguments from the tool call
    argument_hash = tool_call["args"] || {}

    # Convert string keys to symbols for method calling
    argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
      memo[k.to_sym] = v
      memo
    end

    # Check if Gemini wrapped arguments in an "options" key and unwrap them
    if argument_hash.keys == [:options] && argument_hash[:options].is_a?(Hash)
      argument_hash = argument_hash[:options]
      # Convert the unwrapped hash keys to symbols as well
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end
    end

    # Inject session for tools that need it (e.g., monadic state tools, image generators)
    # Check if the method accepts a :session parameter and inject it if so
    method_obj = APPS[app]&.method(function_name.to_sym) rescue nil
    if method_obj && method_obj.parameters.any? { |type, name| name == :session }
      argument_hash[:session] = session
    end

    # Special handling for tavily_search to ensure proper parameter mapping
    if function_name == "tavily_search"
      clean_args = {}
      clean_args[:query] = argument_hash[:query] || argument_hash[:q] if argument_hash[:query] || argument_hash[:q]
      clean_args[:n] = argument_hash[:n] || argument_hash[:max_results] || 3
      argument_hash = clean_args
    end

    argument_hash
  end

  # 3b: Look up and invoke the tool function on the app instance or self
  def invoke_gemini_tool_function(app, function_name, argument_hash)
    function_return = if APPS[app] && APPS[app].respond_to?(function_name.to_sym)
      APPS[app].send(function_name.to_sym, **argument_hash)
    elsif respond_to?(function_name.to_sym)
      send(function_name.to_sym, **argument_hash)
    else
      raise NoMethodError, "Function '#{function_name}' not found in app or helper"
    end

    Monadic::Utils::ExtraLogger.log { "[DEBUG Tools] #{function_name} returned: #{function_return.to_s[0..500]}" }

    function_return
  end

  # 3c: Process tool return value for media generators and standard functions
  def handle_media_generation_result(function_name, function_return, session)
    if function_name == "generate_video_with_veo"
      video_filename = nil
      video_success = false
      error_message = nil

      begin
        if function_return.is_a?(String)
          parsed_json = JSON.parse(function_return)

          if parsed_json["videos"] && !parsed_json["videos"].empty?
            video_success = true
          elsif !parsed_json["success"]
            error_message = parsed_json["message"]
            video_success = false
          end
        end
      rescue JSON::ParserError => e
        if function_return.to_s.include?("saved video") ||
           function_return.to_s.include?("Successfully") ||
           function_return.to_s =~ /\d{10}_\d+_\d+x\d+\.mp4/
          video_success = true
        end
      end

      if video_success
        function_return.is_a?(String) ? function_return : function_return.to_json
      elsif error_message
        "Video generation failed: #{error_message}"
      else
        function_return.is_a?(String) ? function_return : function_return.to_json
      end
    elsif function_name == "generate_image_with_gemini"
      image_success = false
      error_message = nil

      begin
        if function_return.is_a?(String)
          parsed_json = JSON.parse(function_return)

          if parsed_json["success"]
            image_success = true
          else
            error_message = parsed_json["error"]
            image_success = false
          end
        end
      rescue JSON::ParserError => e
        if function_return.to_s.include?("success") && function_return.to_s.include?("filename")
          image_success = true
        end
      end

      if image_success
        function_return.is_a?(String) ? function_return : function_return.to_json
      elsif error_message
        "Image generation failed: #{error_message}"
      else
        function_return.is_a?(String) ? function_return : function_return.to_json
      end
    elsif function_name == "generate_image_with_gemini3_preview"
      image_success = false
      error_message = nil
      generated_filename = nil

      begin
        if function_return.is_a?(String)
          parsed_json = JSON.parse(function_return)

          if parsed_json["success"] && parsed_json["filename"]
            image_success = true
            generated_filename = parsed_json["filename"]

            session[:gemini3_last_image] = generated_filename
            session[:gemini3_duplicate_check] = true

            Monadic::Utils::ExtraLogger.log { "Gemini3Preview: Saved last generated image: #{generated_filename}\n  Set duplicate check flag" }
          else
            error_message = parsed_json["error"]
            image_success = false
          end
        end
      rescue JSON::ParserError => e
        if function_return.to_s.include?("success") && function_return.to_s.include?("filename")
          image_success = true
        end
      end

      if image_success
        function_return.is_a?(String) ? function_return : function_return.to_json
      elsif error_message
        "Image generation failed: #{error_message}"
      else
        function_return.is_a?(String) ? function_return : function_return.to_json
      end
    else
      # Standard handling for other functions
      if function_return.is_a?(Hash) && function_return[:_image]
        session[:pending_tool_images] = Array(function_return[:_image])
        clean_return = function_return.reject { |k, _| k.to_s.start_with?("_") }
        content = JSON.generate(clean_return)
      else
        content = function_return.is_a?(String) ? function_return : function_return.to_json
      end

      if function_return.is_a?(Hash) && function_return[:gallery_html]
        session[:tool_html_fragments] ||= []
        session[:tool_html_fragments] << function_return[:gallery_html]
      end

      content
    end
  end

  # 3d: Handle errors during tool function execution (video filename extraction, content policy)
  def handle_gemini_tool_execution_error(e, function_name, argument_hash, session_params, &block)
    error_message = Monadic::Utils::ErrorFormatter.tool_error(
      provider: "Gemini",
      tool_name: function_name,
      message: e.message
    )
    STDERR.puts error_message

    if function_name == "generate_video_with_veo"
      video_success = false
      video_filename = nil

      if e.message =~ /Successfully saved video to: .*?\/(\d+_\d+_\d+x\d+\.mp4)/ ||
         e.message =~ /(\d{10}_\d+_\d+x\d+\.mp4)/ ||
         e.message =~ /Created placeholder video file at: .*?\/(\d+_\d+_\d+x\d+\.mp4)/
        video_filename = $1
        video_success = true
      end

      if video_filename && video_success
        STDERR.puts "Found video filename in error: #{video_filename}"

        original_prompt = ""
        begin
          original_prompt = argument_hash[:prompt].to_s if argument_hash && argument_hash[:prompt]
        rescue StandardError
          original_prompt = "Video generation"
        end

        success_content = "Successfully saved video to: /data/#{video_filename}\nOriginal prompt: #{original_prompt}"

        session_params["tool_results"] << {
          "functionResponse" => {
            "name" => function_name,
            "response" => {
              "name" => function_name,
              "content" => success_content
            }
          }
        }
      else
        error_details = e.message.to_s
        if error_details =~ /content\s+policy\s+violation/i || error_details =~ /responsible\s+AI/i || error_details =~ /safety/i
          custom_error_message = "Video generation failed: The prompt appears to violate content policy guidelines. Please try a different prompt with less sensitive content."
          session_params["tool_results"] << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => custom_error_message
              }
            }
          }
        else
          session_params["tool_results"] << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => error_message
              }
            }
          }
        end
      end
    else
      session_params["tool_results"] << {
        "functionResponse" => {
          "name" => function_name,
          "response" => {
            "name" => function_name,
            "content" => error_message
          }
        }
      }
    end

    res = { "type" => "fragment", "content" => "<span class='text-danger'>#{error_message}</span>", "sequence" => 0, "timestamp" => Time.now.to_f, "is_first" => true }
    block&.call res
  end

  def translate_role(role)
    case role
    when "user"
      "user"
    when "assistant"
      "model"
    when "system"
      "user"
    else
      role.downcase
    end
  end
  
  # Helper method to unwrap content from a single Markdown code block
  def unwrap_single_markdown_code_block(content)
    return content unless content.is_a?(String)
    
    # Strip leading/trailing whitespace to normalize
    trimmed = content.strip
    
    # Check if the entire content is wrapped in a single code block
    # Pattern: starts with ``` (optionally with language), ends with ```
    # and has no other ``` in between
    if trimmed =~ /\A```(?:html|HTML|xml|XML|markdown|md|)?\s*\n(.*)\n```\z/m
      inner_content = $1
      
      # Verify there are no nested code blocks
      if !inner_content.include?('```')
        return inner_content
      end
    end
    
    # Return original content if not a single code block
    content
  end
  
  public

  # Helper function to generate video with Veo model
  def generate_video_with_veo(prompt:, image_path: nil, aspect_ratio: "16:9", number_of_videos: nil, person_generation: nil, negative_prompt: nil, duration_seconds: nil, veo_model: nil, session: nil)

    # Try to get image data from session and create temporary file
    actual_image_path = nil
    temp_file_path = nil

    # Use uploaded image from session if image_path is not explicitly provided
    if image_path.nil? && session && session[:messages]
      # Look for the most recent user message with non-empty images
      user_messages_with_images = session[:messages].select { |msg| msg["role"] == "user" && msg["images"] && msg["images"].any? }

      if user_messages_with_images.any?
        latest_message = user_messages_with_images.last

        if latest_message["images"] && latest_message["images"].first
          # Extract image data from the first image
          first_image = latest_message["images"].first
          
          # Get the base64 data from the session
          if first_image["data"] && first_image["data"].start_with?("data:image/")
            # Create a temporary file from the base64 data
            require 'tempfile'
            require 'base64'
            
            # Extract the base64 data
            data_url = first_image["data"]
            # Split the data URL to get the base64 part
            base64_data = data_url.split(',').last
            # Decode the base64 data
            image_binary = Base64.decode64(base64_data)
            
            # Determine file extension and mime type from data URL or session data
            detected_mime_type = nil
            if first_image["type"]
              detected_mime_type = first_image["type"]
            elsif data_url.include?('image/')
              detected_mime_type = data_url.split(';').first.split(':').last
            end
            
            extension = case detected_mime_type
                       when 'image/jpeg', 'image/jpg' then '.jpg'
                       when 'image/png' then '.png'
                       when 'image/gif' then '.gif'
                       when 'image/webp' then '.webp'
                       else
                         # Try to detect from data URL if mime type is not available
                         if data_url.include?('image/jpeg')
                           '.jpg'
                         elsif data_url.include?('image/png')
                           '.png'
                         elsif data_url.include?('image/gif')
                           '.gif'
                         elsif data_url.include?('image/webp')
                           '.webp'
                         else
                           '.jpg' # default
                         end
                       end
            
            
            # Create temporary file in shared data directory
            # This ensures the file is accessible both locally and in Docker container
            data_paths = ["/monadic/data/", "#{Dir.home}/monadic/data/"]
            temp_dir = nil
            
            # Find or create the data directory
            data_paths.each do |path|
              if Dir.exist?(path)
                temp_dir = path
                break
              else
                begin
                  FileUtils.mkdir_p(path)
                  temp_dir = path
                  break
                rescue StandardError
                  next
                end
              end
            end
            
            if temp_dir
              # Create a unique filename with timestamp and mime type info
              timestamp = Time.now.to_i
              temp_filename = "video_gen_temp_#{timestamp}_#{rand(1000)}#{extension}"
              temp_file_path = File.join(temp_dir, temp_filename)
              
              # Store mime type information in a companion file for reference
              mime_info_path = temp_file_path + ".mime"
              
              # Check and potentially resize image before writing
              begin
                # Check image size
                image_size = image_binary.size
                
                # Check image size against Vertex AI limits (20MB)
                if image_size > 20 * 1024 * 1024
                  STDERR.puts "ERROR: Image is too large (#{image_size} bytes). Maximum supported size is 20MB."
                  actual_image_path = nil
                elsif image_size > 10 * 1024 * 1024
                  STDERR.puts "WARNING: Image is large (#{image_size} bytes). This may take longer to process."
                end
                
                # Write the image file and mime type info
                File.open(temp_file_path, 'wb') do |f|
                  f.write(image_binary)
                end
                
                # Write mime type info to companion file
                if detected_mime_type
                  File.write(mime_info_path, detected_mime_type)
                end
                
                actual_image_path = temp_filename  # Use just the filename, not full path

                Monadic::Utils::ExtraLogger.log { "Temp file created successfully:\n  temp_file_path: #{temp_file_path}\n  actual_image_path: #{actual_image_path}" }
              rescue StandardError => e
                STDERR.puts "ERROR: Failed to process image: #{e.message}"
                actual_image_path = nil

                Monadic::Utils::ExtraLogger.log { "ERROR creating temp file: #{e.message}\n  #{e.backtrace.first(3).join("\n  ")}" }
              end
            else
              STDERR.puts "ERROR: Could not create temporary file - no accessible data directory"
            end
            
          elsif first_image["filename"]
            actual_image_path = first_image["filename"]
          elsif first_image["title"]
            actual_image_path = first_image["title"]
          else
          end
        else
        end
      else
      end
    else
    end
    
    # Use session image path if available, otherwise use provided image_path (but ignore "image_path" literal)
    final_image_path = actual_image_path
    if !final_image_path && image_path && image_path != "image_path"
      final_image_path = image_path
    end
    
    # If still nil, fall back to last video image stored in session
    if !final_image_path && session && session[:gemini_last_video_image]
      final_image_path = session[:gemini_last_video_image]
    end

    Monadic::Utils::ExtraLogger.log { "Final image path decision:\n  actual_image_path (from session): #{actual_image_path.inspect}\n  image_path (from LLM param): #{image_path.inspect}\n  final_image_path (used): #{final_image_path.inspect}" }

    # Construct the command
    # Use shellwords to properly escape all parameters
    require 'shellwords'
    
    # Veo 3 specifications (fixed values)
    # - Resolution: 720p
    # - Frame Rate: 24 fps
    # - Duration: 8 seconds
    # - Aspect Ratio: 16:9 only
    # - Videos per request: 1
    
    parts = []
    parts << "video_generator_gemini.rb"
    parts << "-p"
    parts << prompt.to_s
    parts << "-a"
    parts << "16:9"  # Always use 16:9 for Veo 3
    parts << "-n"
    parts << "1"  # Always force number_of_videos to 1
    
    # Add negative prompt if provided
    if negative_prompt && !negative_prompt.to_s.empty?
      parts << "--negative-prompt"
      parts << negative_prompt.to_s
    end
    
    # Person generation is auto-selected based on image presence
    # Don't specify it manually - let the script handle it
    
    # Add image path if available (should be filename only from ~/monadic/data/)
    if final_image_path && !final_image_path.empty?
      parts << "-i"
      parts << final_image_path
      
      # Persist for follow-up runs (only store filename portion)
      session[:gemini_last_video_image] = File.basename(final_image_path) if session
    else
    end
    
    # Select model speed (default fast). veo_model: 'fast'|'quality' or full model id
    if veo_model && !veo_model.to_s.empty?
      vm = veo_model.to_s.strip.downcase
      if vm == 'quality' || vm.include?('veo-3.1-generate-preview') || vm.include?('veo-3.0-generate-001')
        parts << "--quality"
      elsif vm == 'fast' || vm.include?('veo-3.1-fast-generate-preview') || vm.include?('veo-3.0-fast-generate-001')
        parts << "--fast"
      end
    end

    # Create the bash command using Shellwords.join for proper escaping
    cmd = "bash -c #{Shellwords.escape(Shellwords.join(parts))}"
    
    begin
      # Send command and get raw output
      result_json = send_command(command: cmd, container: "ruby")
      
      # Store video filename in session if successful
      if session && result_json.is_a?(String)
        begin
          parsed_result = JSON.parse(result_json)
          if parsed_result["success"] && parsed_result["filename"]
            session[:gemini_last_video_filename] = parsed_result["filename"]
          end
        rescue JSON::ParserError
          # Ignore parsing error
        end
      end

      # Clean up temporary files if we created them
      if temp_file_path && File.exist?(temp_file_path)
        File.unlink(temp_file_path)
        # Also clean up mime info file if it exists
        mime_info_path = temp_file_path + ".mime"
        if File.exist?(mime_info_path)
          File.unlink(mime_info_path)
        end
      end
      
      return result_json
    rescue => e
      STDERR.puts "Error executing command: #{e.message}"
      
      # Clean up temporary files even if there was an error
      if temp_file_path && File.exist?(temp_file_path)
        File.unlink(temp_file_path)
        # Also clean up mime info file if it exists
        mime_info_path = temp_file_path + ".mime"
        if File.exist?(mime_info_path)
          File.unlink(mime_info_path)
        end
      end
      return { 
        "success" => false, 
        "message" => "Error executing video generation command: #{e.message}", 
        "original_prompt" => prompt 
      }.to_json
    end
  end
  
  # Helper method to get standard function handling instructions for Gemini models
  # Particularly important for "thinking" models but beneficial for all Gemini integrations
  def self.function_usage_instructions
    <<~INSTRUCTIONS
      IMPORTANT FUNCTION HANDLING GUIDELINES:
      
      1. For internal functions (like check_environment), execute them silently and don't mention them in your response to users.
         Never show these function calls in your response or include them in code blocks.
      
      2. For execution functions (like run_script), call them directly without printing them or storing their results:
         run_script(command="python", code="print('Hello world')", extension="py")
      
      3. When showing code examples to users, display the actual code they should run (e.g., Python code),
         not the function calls you use to execute that code.
      
      4. Begin your conversations with a simple greeting, not with function calls or outputs.
      
      5. All function calls should be made directly without print statements or variable assignments
         for their results. The system automatically handles displaying function results.
         
      6. CRITICAL: HTML elements (img, div, video, audio tags) MUST NEVER be enclosed in code blocks (```).
         When displaying images, plots, or visualizations, place the HTML directly in your response like this:
         
         <div class="generated_image">
           <img src="/data/image_filename.png" />
         </div>
         
         When displaying videos, place the HTML directly in your response like this:
         
         <div class="generated_video">
           <video controls width="100%">
             <source src="/data/video_filename.mp4" type="video/mp4">
             Your browser does not support the video tag.
           </video>
         </div>
         
         Do NOT place this HTML inside a code block. The media will only display if the HTML is outside of code blocks.
         Users will not see visualizations if you wrap HTML in code blocks.
    INSTRUCTIONS
  end

  def generate_image_with_gemini(prompt:, operation: "generate", model: "gemini", session: nil)
    require 'net/http'
    require 'json'
    require 'base64'
    require 'tempfile'
    
    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      return { success: false, error: "GEMINI_API_KEY not configured" }.to_json unless api_key
      
      # For editing operations, force use of Gemini model (Imagen doesn't support editing)
      if operation == "edit"
        model = "gemini"
      end
      
      # If Imagen model is selected for generation, use direct API implementation
      # Supports: imagen3, imagen4, imagen4-ultra, imagen4-fast
      if IMAGE_GENERATION_MODELS.key?(model) && operation == "generate"
        return generate_image_with_imagen_direct(prompt: prompt, model: model)
      end

      # Gemini 3.1 Flash Image Preview uses generateContent on v1beta endpoint
      if model == "gemini-3.1-flash-image-preview" || model == "gemini-3-pro-image-preview"
        # Pass session to support image editing
        return generate_image_with_gemini3_preview(prompt: prompt, model: model, session: session)
      end
      
      # Set up shared folder path
      shared_folder = Monadic::Utils::Environment.shared_volume
      
      # Prepare the request body with corrected structure
      request_body = {
        contents: [{
          parts: []
        }],
        generationConfig: {
          responseModalities: ["TEXT", "IMAGE"],
          temperature: 0.8,
          topK: 40,
          topP: 0.95
        }
      }
      
      # For edit operation, add the uploaded image to the request (natural language editing)
      if operation == "edit" && session
        # Look for the most recent user message with non-empty images
        user_messages_with_images = []
        if session[:messages]
          user_messages_with_images = session[:messages].select { |msg| msg["role"] == "user" && msg["images"] && msg["images"].any? }
        end

        if user_messages_with_images.empty?
          # Check for last generated image if no uploaded image found
          if session[:gemini_last_image]
             filename = session[:gemini_last_image]
             filepath = File.join(shared_folder, filename)
             
             if File.exist?(filepath)
               image_data_binary = File.binread(filepath)
               base64_data = Base64.strict_encode64(image_data_binary)
               
               # Determine mime type from extension
               extension = File.extname(filename).downcase
               mime_type = case extension
                           when ".png" then "image/png"
                           when ".jpg", ".jpeg" then "image/jpeg"
                           when ".webp" then "image/webp"
                           else "image/png"
                           end
               
               images = [{
                 "name" => filename,
                 "data" => "data:#{mime_type};base64,#{base64_data}"
               }]
             else
               # Clear stale reference
               session[:gemini_last_image] = nil
               return { success: false, error: "Previous generated image file not found: #{filename}" }.to_json
             end
          else
            return { success: false, error: "No image found for editing. Please upload an image first or generate one." }.to_json
          end
        else
          latest_message = user_messages_with_images.last
          images = latest_message["images"]
        end
        
        # Find the first non-mask image (ignore mask__ prefixed files)
        original_image = images.find { |img| img["name"] && !img["name"].start_with?("mask__") }
        
        if original_image.nil?
          original_image = images.first # Fallback to first image if no non-mask found
        end
        
        Monadic::Utils::ExtraLogger.log { "Gemini Edit: Using natural language editing\n  Image: #{original_image['name']}\n  Edit prompt: #{prompt}" }
        
        if original_image && original_image["data"] && original_image["data"].start_with?("data:image/")
          # Add original image
          original_data_url = original_image["data"]
          original_base64 = original_data_url.split(',').last
          original_mime_type = original_data_url.include?('image/') ? 
                               original_data_url.split(';').first.split(':').last : 
                               "image/jpeg"
          
          request_body[:contents][0][:parts] << {
            inline_data: {
              mime_type: original_mime_type,
              data: original_base64
            }
          }
          
          # Add natural language editing prompt
          edit_prompt = "Please edit this image according to the following instructions: #{prompt}\n\n" +
                       "Make the edits look natural and seamless with the rest of the image."
          
          request_body[:contents][0][:parts] << {
            text: edit_prompt
          }
        else
          return { success: false, error: "Invalid image data format" }.to_json
        end
      else
        # For generate operation, just add the text prompt
        request_body[:contents][0][:parts] << {
          text: prompt
        }
      end
      
      # Make API request
      # Use the new image generation model (stable version)
      model_name = "gemini-3.1-flash-image-preview"
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{api_key}")

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
        http.request(request)
      end
      
      if response.code == '200'
        result = JSON.parse(response.body)
        
        
        # Extract generated image from response
        if result["candidates"] && result["candidates"][0]
          candidate = result["candidates"][0]
          
          if candidate["content"] && candidate["content"]["parts"]
            parts = candidate["content"]["parts"]
            
            # Look for image data in parts
            image_found = false
            parts.each_with_index do |part, index|
              
              if part["inlineData"] && part["inlineData"]["mimeType"] && part["inlineData"]["mimeType"].start_with?("image/")
                # Found image data
                image_found = true
                image_data = Base64.decode64(part["inlineData"]["data"])
                timestamp = Time.now.to_i
                
                # Determine file extension from mime type
                extension = case part["inlineData"]["mimeType"]
                           when "image/png" then "png"
                           when "image/jpeg", "image/jpg" then "jpg"
                           when "image/webp" then "webp"
                           else "png"
                           end
                
                filename = "gemini_#{operation}_#{timestamp}.#{extension}"
                filepath = File.join(shared_folder, filename)
                
                File.open(filepath, 'wb') do |f|
                  f.write(image_data)
                end
                
                
                return { 
                  success: true, 
                  filename: filename,
                  operation: operation,
                  prompt: prompt,
                  model: "gemini"
                }.to_json
              elsif part["inline_data"] && part["inline_data"]["mime_type"] && part["inline_data"]["mime_type"].start_with?("image/")
                # Alternative key naming (inline_data vs inlineData)
                image_found = true
                image_data = Base64.decode64(part["inline_data"]["data"])
                timestamp = Time.now.to_i
                
                extension = case part["inline_data"]["mime_type"]
                           when "image/png" then "png"
                           when "image/jpeg", "image/jpg" then "jpg"
                           when "image/webp" then "webp"
                           else "png"
                           end
                
                filename = "gemini_#{operation}_#{timestamp}.#{extension}"
                filepath = File.join(shared_folder, filename)
                
                File.open(filepath, 'wb') do |f|
                  f.write(image_data)
                end
                
                
                return { 
                  success: true, 
                  filename: filename,
                  operation: operation,
                  prompt: prompt,
                  model: "gemini"
                }.to_json
              end
            end
            
          end
        end
        
        # If no image was found in response
        return { 
          success: false, 
          error: "No image was generated. Response parts: #{result["candidates"]&.first&.dig("content", "parts")&.map { |p| p.keys }}"
        }.to_json
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "API request failed with status #{response.code}"
        return { success: false, error: error_message }.to_json
      end
      
    rescue StandardError => e
      return { success: false, error: Monadic::Utils::ErrorFormatter.tool_error(
        provider: "Gemini",
        tool_name: "generate_image_with_gemini",
        message: e.message
      ) }.to_json
    end
  end


  # Direct Imagen API implementation (supports imagen3, imagen4, imagen4-ultra, imagen4-fast)
  def generate_image_with_imagen_direct(prompt:, aspect_ratio: "1:1", sample_count: 1, person_generation: "ALLOW_ADULT", model: "imagen4-fast")
    require 'net/http'
    require 'json'
    require 'base64'

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      return { success: false, error: "GEMINI_API_KEY not configured" }.to_json unless api_key


      # Set up shared folder path
      shared_folder = Monadic::Utils::Environment.shared_volume

      # Prepare the request body for Imagen
      request_body = {
        instances: [{
          prompt: prompt
        }],
        parameters: {
          sampleCount: sample_count,
          aspectRatio: aspect_ratio,
          personGeneration: person_generation
        }
      }

      # Resolve model name
      # Supports: imagen3, imagen4, imagen4-ultra, imagen4-fast
      # Defaults to imagen4-fast for best performance
      image_model = IMAGE_GENERATION_MODELS[model] || IMAGE_GENERATION_MODEL
      # system_info: Using image_model #{image_model} for generation

      # Make API request to Imagen
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{image_model}:predict?key=#{api_key}")

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 300) do |http|
        http.request(request)
      end
      
      if response.code == '200'
        result = JSON.parse(response.body)
        
        # Process Imagen response
        if result["predictions"] && !result["predictions"].empty?
          prediction = result["predictions"].first
          
          if prediction["bytesBase64Encoded"]
            # Save the generated image
            image_data = Base64.decode64(prediction["bytesBase64Encoded"])
            timestamp = Time.now.to_i
            # Use model parameter for filename (e.g., imagen4-fast, imagen3, etc.)
            model_prefix = model.gsub('-', '_')
            filename = "#{model_prefix}_#{timestamp}_0_#{aspect_ratio.gsub(':', 'x')}.png"
            filepath = File.join(shared_folder, filename)

            File.open(filepath, 'wb') do |f|
              f.write(image_data)
            end

            result = {
              success: true,
              filename: filename,
              operation: "generate",
              prompt: prompt,
              model: model
            }.to_json
            return result
          end
        end

        # If no image was found in response
        error_result = {
          success: false,
          error: "No image was generated by Imagen. Response: #{result}"
        }.to_json
        return error_result
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig("error", "message") || "API request failed with status #{response.code}"
        return { success: false, error: error_message }.to_json
      end
      
    rescue StandardError => e
      return { success: false, error: "Error with Imagen: #{e.message}" }.to_json
    end
  end
end
