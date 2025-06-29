# frozen_string_literal: true

require 'fileutils'
require 'base64'
require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/debug_helper"
require_relative "../../monadic_provider_interface"
require_relative "../../monadic_schema_validator"
require_relative "../../monadic_performance"
module OpenAIHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
  include MonadicProviderInterface
  include MonadicSchemaValidator
  include MonadicPerformance
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.openai.com/v1"

  OPEN_TIMEOUT = 20
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  MODELS_N_LATEST = -1

  # partial string match
  EXCLUDED_MODELS = [
    "vision",
    "instruct",
    "realtime",
    "audio",
    "moderation",
    "embedding",
    "tts",
    "davinci",
    "babbage",
    "turbo",
    "dall-e",
    "whisper",
    "gpt-3.5",
    "gpt-4-",
    "o1-preview",
    "search",
    "trascribe",
    "computer-use",
    "image"
  ]

  # partial string match
  REASONING_MODELS = [
    "o3",
    "o4",
    "o1"
  ]

  # complete string match
  NON_TOOL_MODELS = [
    "o1",
    "o1-2024-12-17",
    "o1-mini",
    "o1-mini-2024-09-12",
    "o1-preview",
    "o1-preview-2024-09-12"
  ]

  # complete string match
  SEARCH_MODELS = [
    "gpt-4.1",
    "gpt-4.1-mini",
  ]

  # complete string match
  NON_STREAM_MODELS = [
    "o1-pro",
    "o1-pro-2025-03-19",
    "o3-pro"
  ]
  
  # Models that require the new responses API endpoint
  RESPONSES_API_MODELS = [
    "o3-pro",
    "o3",
    "o4-mini"
  ]
  
  # Models that use responses API for web search
  RESPONSES_API_WEBSEARCH_MODELS = [
    "gpt-4.1",
    "gpt-4.1-mini",
    "o3",
    "o3-pro",
    "o4-mini"
  ]

  # Native OpenAI web search tool configuration for responses API
  NATIVE_WEBSEARCH_TOOL = {
    type: "web_search_preview"
  }
  
  # Built-in tools available in Responses API
  RESPONSES_API_BUILTIN_TOOLS = {
    "web_search" => { type: "web_search_preview" },
    "file_search" => ->(vector_store_ids: [], max_num_results: 20) {
      {
        type: "file_search",
        vector_store_ids: vector_store_ids,
        max_num_results: max_num_results
      }
    },
    "code_interpreter" => { type: "code_interpreter" },
    "computer_use" => ->(display_width: 1280, display_height: 720) {
      {
        type: "computer_use",
        display_width: display_width,
        display_height: display_height
      }
    },
    "image_generation" => { type: "image_generation" },
    "mcp" => ->(method:, server:) {
      {
        type: "mcp",
        method: method,
        server: server
      }
    }
  }


  WEBSEARCH_PROMPT = <<~TEXT

    Web search is enabled for this conversation. You should proactively use web search whenever:
    - The user asks about current events, news, or recent information
    - The user asks about specific people, companies, organizations, or entities
    - The user asks questions that would benefit from up-to-date or factual information
    - You need to verify facts or get the latest information about something
    - The user asks "who is" or similar questions about people or entities
    
    You don't need to ask permission to search - just search when it would be helpful. The web search happens automatically when you need it.

    Always ensure that your answers are comprehensive, accurate, and support the user's needs with relevant citations. When you find information through web search, provide detailed and informative responses.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs. Example: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT
  


  class << self
    attr_reader :cached_models

    def vendor_name
      "OpenAI"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:openai] if $MODELS[:openai]

      api_key = CONFIG["OPENAI_API_KEY"]
      return [] if api_key.nil?

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{api_key}"
      }

      target_uri = "#{API_ENDPOINT}/models"
      http = HTTP.headers(headers)

      begin
        res = http.get(target_uri)

        if res.status.success?
          begin
            res_body = JSON.parse(res.body)
          rescue JSON::ParserError => e
            DebugHelper.debug("Invalid JSON from OpenAI models API: #{res.body[0..200]}", "api", level: :error)
            return []
          end
          
          if res_body && res_body["data"]
            # Cache the filtered and sorted models
            $MODELS[:openai] = res_body["data"].sort_by do |item|
              item["created"]
            end.reverse[0..MODELS_N_LATEST].map do |item|
              item["id"]
              # Filter out excluded models, embedding each string in a regex
            end.reject do |model|
              EXCLUDED_MODELS.any? { |excluded_model| /\b#{excluded_model}\b/ =~ model }
            end
            $MODELS[:openai]
          end
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:openai] = nil
    end
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "gpt-4.1")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    api_key = CONFIG["OPENAI_API_KEY"]
    
    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Basic request body
    body = {
      "model" => model,
      "stream" => false
    }
    
    # Add messages from options if available
    if options["messages"]
      body["messages"] = options["messages"]
    elsif options["message"]
      body["messages"] = [{ "role" => "user", "content" => options["message"] }]
    end
    
    # Add temperature if specified
    body["temperature"] = options["temperature"].to_f if options["temperature"]
    
    # Add response_format if specified (for structured JSON output)
    if options["response_format"] || options[:response_format]
      response_format = options["response_format"] || options[:response_format]
      body["response_format"] = response_format.is_a?(Hash) ? response_format : { "type" => "json_object" }
      
      DebugHelper.debug("Using response format: #{body['response_format'].inspect}", "api")
    end
    
    # Set API endpoint
    target_uri = API_ENDPOINT + "/chat/completions"

    # Make the request
    http = HTTP.headers(headers)
   
    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      break if res && res.status && res.status.success?
      sleep RETRY_DELAY
    end

    # Process response
    if res && res.status && res.status.success?
      # Properly read response body content
      response_body = res.body.respond_to?(:read) ? res.body.read : res.body.to_s
      parsed_response = JSON.parse(response_body)
      return parsed_response.dig("choices", 0, "message", "content")
    else
      # Properly read error response body content
      error_body = res && res.body ? (res.body.respond_to?(:read) ? res.body.read : res.body.to_s) : nil
      error_response = error_body ? JSON.parse(error_body) : { "error" => "No response received" }
      return "ERROR: #{error_response["error"]["message"] || error_response["error"]}"
    end
  rescue StandardError => e
    return "Error: #{e.message}"
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    
    app = obj["app_name"]
    api_key = CONFIG["OPENAI_API_KEY"]

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    reasoning_effort = obj["reasoning_effort"]

    # Handle max_tokens, prioritizing AI_USER_MAX_TOKENS for AI User mode
    if obj["ai_user"] == "true"
      max_completion_tokens = CONFIG["AI_USER_MAX_TOKENS"]&.to_i || obj["max_completion_tokens"]&.to_i || obj["max_tokens"]&.to_i
    else
      max_completion_tokens = obj["max_completion_tokens"]&.to_i || obj["max_tokens"]&.to_i
    end
    
    # Get image generation flag
    image_generation = obj["image_generation"] == "true"
    
    # Define shared folder path based on environment
    shared_folder = if defined?(IN_CONTAINER) && IN_CONTAINER
                     MonadicApp::SHARED_VOL # "/monadic/data"
                    else
                     MonadicApp::LOCAL_SHARED_VOL # "~/monadic/data"
                    end
    
    temperature = obj["temperature"].to_f
    presence_penalty = obj["presence_penalty"].to_f
    frequency_penalty = obj["frequency_penalty"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    # Store the original model for comparison later
    original_user_model = model
    
    # Check if original model requires responses API
    use_responses_api = RESPONSES_API_MODELS.include?(original_user_model)
    
    # Check if web search is enabled in settings
    websearch_enabled = obj["websearch"] == "true"
    
    # Check if we should use responses API with native websearch
    # This happens when:
    # 1. Web search is enabled in settings
    # 2. Model supports it (gpt-4.1 or gpt-4.1-mini)
    use_responses_api_for_websearch = websearch_enabled && 
                                     RESPONSES_API_WEBSEARCH_MODELS.include?(model)
    
    # OpenAI only uses native web search, no Tavily support
    
    # Store these variables in obj for later use in the method
    obj["websearch_enabled"] = websearch_enabled
    obj["use_responses_api_for_websearch"] = use_responses_api_for_websearch
    
    # Update use_responses_api flag if we need it for websearch
    if use_responses_api_for_websearch && !use_responses_api
      use_responses_api = true
    end

    message = nil
    data = nil

    if role != "tool"
      message = obj["message"].to_s
      
      # Reset model switch notification flag for new user messages
      if role == "user"
        session.delete(:model_switch_notified)
      end

      # Apply monadic transformation if needed (for display purposes only)
      # The actual API transformation happens later when building messages

      html = markdown_to_html(message, mathjax: obj["mathjax"])

      if message != "" && role == "user"

        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "role" => role,
                  "lang" => detect_language(message)
                } }
        res["content"]["images"] = obj["images"] if obj["images"]
        block&.call res
        session[:messages] << res["content"]
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    session[:messages] ||= []
    session[:messages].each { |msg| msg["active"] = false if msg }
    context = [session[:messages].first].compact
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size).compact
    end
    context.each { |msg| msg["active"] = true if msg }

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
    }

    reasoning_model = REASONING_MODELS.any? { |reasoning_model| /\b#{reasoning_model}\b/ =~ model }
    non_stream_model = NON_STREAM_MODELS.any? { |non_stream_model| /\b#{non_stream_model}\b/ =~ model }
    non_tool_model = NON_TOOL_MODELS.any? { |non_tool_model| /\b#{non_tool_model}\b/ =~ model }
    search_model = SEARCH_MODELS.any? { |search_model| /\b#{search_model}\b/ =~ model }
    
    # If websearch is enabled and the current model is a reasoning model without native search,
    # switch to the WEBSEARCH_MODEL (defaults to gpt-4.1-mini if not set)
    if websearch_enabled && reasoning_model && !search_model && !use_responses_api
      original_model = model
      model = CONFIG["WEBSEARCH_MODEL"] || "gpt-4.1-mini"
      body["model"] = model
      
      # Update model flags after switching
      reasoning_model = REASONING_MODELS.any? { |reasoning_model| /\b#{reasoning_model}\b/ =~ model }
      non_stream_model = NON_STREAM_MODELS.any? { |non_stream_model| /\b#{non_stream_model}\b/ =~ model }
      non_tool_model = NON_TOOL_MODELS.any? { |non_tool_model| /\b#{non_tool_model}\b/ =~ model }
      search_model = SEARCH_MODELS.any? { |search_model| /\b#{search_model}\b/ =~ model }
      
      # Send system notification about model switch
      if block && original_model != model
        system_msg = {
          "type" => "system_info",
          "content" => "Model automatically switched from #{original_model} to #{model} for web search functionality."
        }
        block.call system_msg
      end
    end
    
    # Determine which prompt to use based on web search type
    websearch_prompt = if websearch_enabled
                       WEBSEARCH_PROMPT
                     else
                       nil
                     end

    if reasoning_model
      body["reasoning_effort"] = reasoning_effort || "medium"
      body.delete("temperature")
      body.delete("frequency_penalty")
      body.delete("presence_penalty")
      body.delete("max_completion_tokens")
    elsif search_model
      body.delete("n")
      body.delete("temperature")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")
    else
      body["n"] = 1
      body["temperature"] = temperature if temperature
      body["presence_penalty"] = presence_penalty if presence_penalty
      body["frequency_penalty"] = frequency_penalty if frequency_penalty
      body["max_completion_tokens"] = max_completion_tokens if max_completion_tokens 

      if obj["response_format"]
        body["response_format"] = APPS[app].settings["response_format"]
      end

      # Use the new unified interface for monadic mode
      body = configure_monadic_response(body, :openai, app)
    end

    if non_stream_model
      body["stream"] = false
    else
      body["stream"] = true
    end

    if non_tool_model
      body.delete("tools")
      body.delete("response_format")
    else
      # Parse tools if they're sent as JSON string
      tools_param = obj["tools"]
      if tools_param.is_a?(String)
        begin
          tools_param = JSON.parse(tools_param)
        rescue JSON::ParserError
          tools_param = nil
        end
      end
      
      if tools_param && !tools_param.empty?
        # Get tools from app settings, or use the parsed tools from request
        app_tools = APPS[app]&.settings&.[]("tools")
        if app_tools && !app_tools.empty?
          body["tools"] = app_tools
        elsif tools_param.is_a?(Array) && !tools_param.empty?
          # Use tools from request if app doesn't have them
          body["tools"] = tools_param
        else
          body["tools"] = []
        end
        
        # OpenAI uses native web search, no additional tools needed
        
        body["tools"].uniq!
      else
        body.delete("tools")
        body.delete("tool_choice")
      end
    end

    
    # The context is added to the body
    messages_containing_img = false
    image_file_references = []
    
    # Process images if this is an image generation request
    if image_generation && role == "user"
      context.compact.each do |msg|
        if msg["images"]
          msg["images"].each do |img|
            begin
              # Skip if already a reference to shared folder
              next if img["data"].to_s.start_with?("/data/")
              
              # Generate a unique filename
              timestamp = Time.now.to_i
              random_suffix = SecureRandom.hex(4)
              ext = File.extname(img["data"].to_s).empty? ? ".png" : File.extname(img["data"].to_s)
              
              # Check if this is a mask image by looking at the title or is_mask flag
              is_mask = img["is_mask"] == true || img["title"].to_s.start_with?("mask__")
              
              # Use appropriate prefix based on image type
              prefix = is_mask ? "mask__" : "img_"
              new_filename = "#{prefix}#{timestamp}_#{random_suffix}#{ext}"
              target_path = File.join(shared_folder, new_filename)
              
              # Copy the file to shared folder if it exists locally
              if File.exist?(img["data"].to_s)
                FileUtils.cp(img["data"].to_s, target_path)
                # Store the full path for internal use
                image_file_references << "/data/#{new_filename}"
              # Handle data URIs
              elsif img["data"].to_s.start_with?("data:")
                # Extract and save base64 data
                data_uri = img["data"].to_s
                content_type, encoded_data = data_uri.match(/^data:([^;]+);base64,(.+)$/)[1..2]
                decoded_data = Base64.decode64(encoded_data)
                
                # Write to file
                File.open(target_path, 'wb') do |f|
                  f.write(decoded_data)
                end
                
                # Store the full path for internal use
                image_file_references << "/data/#{new_filename}"
              end
            rescue StandardError => e
              puts "Error processing image for generation: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
            end
          end
          
          # Remove images from message to prevent them being sent to vision API
          msg.delete("images")
        end
      end
    end
    
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user" && !image_generation
        msg["images"].each do |img|
          messages_containing_img = true
          if img["type"] == "application/pdf"
            message["content"] << {
              "type" => "file",
              "file" => {
                "file_data" => img["data"],
                "filename" => img["title"]
              }
            }
          else
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
          end
        end
      end
      message
    end

    # "system" role must be replaced with "developer" for reasoning models
    if reasoning_model
      num_system_messages = 0
      body["messages"].each do |msg|
        if msg["role"] == "system"
          msg["role"] = "developer" 
          msg["content"].each do |content_item|
            if content_item["type"] == "text" && num_system_messages == 0
              if websearch_enabled && websearch_prompt
                text = "Web search enabled\n---\n" + content_item["text"] + "\n---\n" + websearch_prompt
              else
                text = "Formatting re-enabled\n---\n" + content_item["text"]
              end
              content_item["text"] = text
            end
          end
          num_system_messages += 1
        end
      end
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    end

    last_text = context.last&.dig("text")

    # Split the last message if it matches /\^__DATA__$/
    if last_text&.match?(/\^\s*__DATA__\s*$/m)
      last_text, data = last_text.split("__DATA__")
      # set last_text to the last message in the context
      context.last["text"] = last_text if context.last
    end

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = message_with_snippet if message_with_snippet.to_s != ""

    # If this is an image generation request, add the image filenames to the last message
    if image_generation && !image_file_references.empty? && role == "user"
      img_references_text = "\n\nAttached images:\n"
      image_file_references.each do |img_path|
        # Extract just the filename without path
        filename = File.basename(img_path)
        img_references_text += "- #{filename}\n"
      end
      
      if last_text.to_s != ""
        last_text += img_references_text
      else
        # If there's no last text, add to the last message in context
        if context.last && context.last["text"]
          context.last["text"] += img_references_text
        end
      end
    end

    if last_text.to_s != "" && prompt_suffix.to_s != ""
      new_text = last_text.to_s + "\n\n" + prompt_suffix.strip
      if body.dig("messages", -1, "content")
        body["messages"].last["content"].each do |content_item|
          if content_item["type"] == "text"
            content_item["text"] = new_text
          end
        end
      end
    end

    if data
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => data.strip }]
      }
      body["prediction"] = {
        "type" => "content",
        "content" => data.strip
      }
    end
    
    # Apply monadic transformation to the last user message for API
    if obj["monadic"].to_s == "true" && body["messages"].any? && 
       body["messages"].last["role"] == "user" && role == "user"
      last_msg = body["messages"].last
      if last_msg["content"].is_a?(Array)
        text_content = last_msg["content"].find { |c| c["type"] == "text" }
        if text_content
          original_text = text_content["text"]
          monadic_text = apply_monadic_transformation(original_text, app, "user")
          text_content["text"] = monadic_text
        end
      end
    end

    # initial prompt in the body is appended with the settings["system_prompt_suffix"
    if initial_prompt.to_s != "" && obj["system_prompt_suffix"].to_s != ""
      new_text = initial_prompt.to_s + "\n\n" + obj["system_prompt_suffix"].strip
      body["messages"].first["content"].each do |content_item|
        if content_item["type"] == "text"
          content_item["text"] = new_text
        end
      end
    end

    if messages_containing_img
      # Check if the current model has vision capability
      # gpt-4.1-mini and gpt-4.1 both have vision capability
      vision_capable_models = ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-preview", "gpt-4.1-mini-2025-04-14", "gpt-4.1-2025-04-14", 
                               "gpt-4.5", "gpt-4.5-preview", "gpt-4o", "gpt-4o-mini", "o3-pro", "o3", "o4-mini"]
      current_model = body["model"]
      has_vision = vision_capable_models.any? { |m| current_model.include?(m) }
      
      unless has_vision || obj["vision_capability"]
        original_model = body["model"]
        body["model"] = "gpt-4.1"
        body.delete("reasoning_effort")
        
        # Send system notification about model switch
        if block && original_model != body["model"]
          system_msg = {
            "type" => "system_info",
            "content" => "Model automatically switched from #{original_model} to #{body['model']} for image processing capability."
          }
          block.call system_msg
        end
      end
      body.delete("stop")
    end

    # Determine which API endpoint to use
    if use_responses_api
      # Use responses API for o3-pro
      target_uri = "#{API_ENDPOINT}/responses"
      
      # Send processing status for long-running models
      if block
        processing_msg = {
          "type" => "processing_status",
          "content" => "This may take a few minutes."
        }
        block.call processing_msg
      end
      
      # Convert messages format to responses API input format
      # Responses API uses different content types than chat API
      input_messages = body["messages"].map do |msg|
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        
        # Skip tool messages for Responses API (they should not be in the input)
        if role == "tool"
          next
        end
        
        # Responses API uses input_text for all text content in the input array
        text_type = "input_text"
        
        # Handle messages with complex content (text + images)
        if content.is_a?(Array)
          # Convert content types for responses API
          converted_content = content.map do |item|
            case item["type"]
            when "text"
              {
                "type" => text_type,
                "text" => item["text"]
              }
            when "image_url"
              # Extract media type and base64 data from data URL
              url = item["image_url"]["url"]
              if url.start_with?("data:")
                match = url.match(/^data:(image\/\w+);base64,(.+)$/)
                if match
                  media_type = match[1]
                  base64_data = match[2]
                else
                  # Default to jpeg if pattern doesn't match
                  media_type = "image/jpeg"
                  base64_data = url.sub(/^data:image\/\w+;base64,/, '')
                end
              else
                # If not a data URL, assume it's already base64
                media_type = "image/jpeg"
                base64_data = url
              end
              
              {
                "type" => "input_image",
                "source" => {
                  "type" => "base64",
                  "media_type" => media_type,
                  "data" => base64_data
                }
              }
            else
              item  # Keep as is for unknown types
            end
          end
          
          {
            "role" => role,
            "content" => converted_content
          }
        else
          # Simple text content
          {
            "role" => role,
            "content" => [
              {
                "type" => text_type,
                "text" => content.to_s
              }
            ]
          }
        end
      end.compact  # Remove nil entries from skipped tool messages
      
      # Create responses API body
      responses_body = {
        "model" => body["model"],
        "input" => input_messages,
        "stream" => body["stream"] || false,  # Default to false for responses API (o3-pro doesn't support streaming yet)
        "store" => true  # Store responses for later retrieval by default
      }
      
      # Add reasoning configuration for reasoning models
      if body["reasoning_effort"]
        responses_body["reasoning"] = {
          "effort" => body["reasoning_effort"]
        }
      end
      
      # Add temperature and sampling parameters if not a reasoning model
      unless reasoning_model
        responses_body["temperature"] = body["temperature"] if body["temperature"]
        responses_body["top_p"] = body["top_p"] if body["top_p"]
      end
      
      # Add max_output_tokens if specified
      if body["max_completion_tokens"] || max_completion_tokens
        responses_body["max_output_tokens"] = body["max_completion_tokens"] || max_completion_tokens
      end
      
      # Add instructions (system prompt) if available
      if body["messages"].first && body["messages"].first["role"] == "developer"
        # Extract the first developer message as instructions
        developer_msg = body["messages"].first
        if developer_msg["content"].is_a?(Array)
          instructions_text = developer_msg["content"].find { |c| c["type"] == "text" }&.dig("text")
        else
          instructions_text = developer_msg["content"]
        end
        
        if instructions_text
          responses_body["instructions"] = instructions_text
          # Remove the developer message from input as it's now in instructions
          input_messages.shift
        end
      end
      
      # Support for stateful conversations (future use)
      if obj["previous_response_id"]
        responses_body["previous_response_id"] = obj["previous_response_id"]
      end
      
      # Support for background processing (future use)
      if obj["background"]
        responses_body["background"] = true
      end
      
      # Support for structured outputs
      if body["response_format"] && body["response_format"]["type"] == "json_object"
        responses_body["text"] = {
          "format" => {
            "type" => "json",
            "json_schema" => body["response_format"]["json_schema"] || {
              "name" => "response",
              "schema" => {
                "type" => "object",
                "additionalProperties" => true
              }
            }
          }
        }
      end
      
      # Add web search tool for responses API if needed
      if obj["use_responses_api_for_websearch"]
        # Add native web search tool for responses API
        responses_body["tools"] = [NATIVE_WEBSEARCH_TOOL]
        
      # Native web search is now supported for o3, o3-pro, and o4-mini models
      end
      
      # Enhanced tool support for responses API
      # Check if we have tools to add (either built-in or custom functions)
      if (body["tools"] && !body["tools"].empty?) || obj["responses_api_tools"]
        responses_body["tools"] ||= []
        
        # Add built-in tools if specified
        if obj["responses_api_tools"]
          obj["responses_api_tools"].each do |tool_name, config|
            if RESPONSES_API_BUILTIN_TOOLS[tool_name]
              tool_def = RESPONSES_API_BUILTIN_TOOLS[tool_name]
              # Handle tools that are lambdas (need configuration)
              if tool_def.is_a?(Proc)
                responses_body["tools"] << tool_def.call(**config)
              else
                responses_body["tools"] << tool_def
              end
            end
          end
        end
        
        # Add custom function tools if available and not using websearch-only mode
        if body["tools"] && !body["tools"].empty? && !obj["use_responses_api_for_websearch"]
          # Convert function tools to Responses API format
          # Responses API expects a flat structure for functions
          function_tools = body["tools"].map do |tool|
            tool_json = JSON.parse(tool.to_json)
            
            if tool_json["type"] == "function" && tool_json["function"]
              {
                "type" => "function",
                "name" => tool_json["function"]["name"],
                "description" => tool_json["function"]["description"],
                "parameters" => tool_json["function"]["parameters"]
              }
            else
              tool_json
            end
          end
          
          responses_body["tools"].concat(function_tools)
        end
        
        # Set tool_choice if specified
        if body["tool_choice"]
          responses_body["tool_choice"] = body["tool_choice"]
        end
        
        # Enable parallel tool calls by default
        responses_body["parallel_tool_calls"] = true
        
      end
      
      # Use responses body instead
      body = responses_body
      
    else
      # Use standard chat/completions API
      target_uri = "#{API_ENDPOINT}/chat/completions"
      
      body["messages"].each do |msg|
        next unless msg["tool_calls"] || msg[:tool_call]

        if !msg["role"] && !msg[:role]
          msg["role"] = "assistant"
        end
        tool_calls = msg["tool_calls"] || msg[:tool_call]
        tool_calls.each do |tool_call|
          tool_call.delete("index")
        end
      end
    end
    
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    # Use longer timeout for responses API as o3-pro can take minutes
    timeout_settings = if use_responses_api
                        {
                          connect: OPEN_TIMEOUT,
                          write: WRITE_TIMEOUT,
                          read: 600  # 10 minutes for o3-pro
                        }
                      else
                        {
                          connect: OPEN_TIMEOUT,
                          write: WRITE_TIMEOUT,
                          read: READ_TIMEOUT
                        }
                      end


    MAX_RETRIES.times do
      res = http.timeout(**timeout_settings).post(target_uri, json: body)
      break if res.status.success?

      sleep RETRY_DELAY
    end

    unless res.status.success?
      
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      formatted_error = format_api_error(error_report, "openai")
      res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
      block&.call res
      return [res]
    end

    # return Array
    if !body["stream"]
      obj = JSON.parse(res.body)
      
      if use_responses_api
        # Handle non-streaming responses API response
        # Support multiple possible response structures
        frag = ""
        
        
        # Try different paths for output
        if obj.dig("response", "output")
          output_array = obj.dig("response", "output")
        elsif obj["output"]
          output_array = obj["output"]
        else
          output_array = []
        end
        
        
        # Extract text from output array
        output_array.each do |item|
          
          if item.is_a?(Hash)
            # Direct text type
            if item["type"] == "text" && item["text"]
              frag += item["text"]
            # Message type with content array
            elsif item["type"] == "message" && item["content"]
              if item["content"].is_a?(Array)
                item["content"].each do |content_item|
                  # Handle both "text" and "output_text" types
                  if (content_item["type"] == "text" || content_item["type"] == "output_text") && content_item["text"]
                    frag += content_item["text"]
                  end
                end
              elsif item["content"].is_a?(String)
                frag += item["content"]
              end
            end
          end
        end
        
        # Fallback to standard format if available
        if frag.empty? && obj.dig("choices", 0, "message", "content")
          frag = obj.dig("choices", 0, "message", "content")
        end
      else
        # Handle standard chat API response
        frag = obj.dig("choices", 0, "message", "content")
      end
      
      
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      
      # For responses API, we need to format the response to match standard structure
      if use_responses_api
        formatted_response = {
          "choices" => [{
            "message" => {
              "role" => "assistant",
              "content" => frag
            },
            "finish_reason" => "stop"
          }],
          "model" => obj["model"] || body["model"]
        }
        [formatted_response]
      else
        [obj]
      end
    else
      # Include original model in the query for comparison
      body["original_user_model"] = original_user_model
      
      if use_responses_api
        # Process responses API streaming response
        process_responses_api_data(app: app,
                                  session: session,
                                  query: body,
                                  res: res.body,
                                  call_depth: call_depth, &block)
      else
        # Process standard chat API streaming response
        process_json_data(app: app,
                          session: session,
                          query: body,
                          res: res.body,
                          call_depth: call_depth, &block)
      end
    end
  rescue HTTP::Error, HTTP::TimeoutError
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY
      retry
    else
      pp error_message = "The request has timed out."
      res = { "type" => "error", "content" => "HTTP ERROR: #{error_message}" }
      block&.call res
      [res]
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}\n#{e.backtrace}\n#{e.inspect}" }
    block&.call res
    [res]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]
    reasoning_model = REASONING_MODELS.any? { |reasoning_model| /\b#{reasoning_model}\b/ =~ obj["model"] }

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      begin
        break if /\Rdata: [DONE]\R/ =~ buffer
      rescue
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      pattern = /data: (\{.*?\})(?=\n|\z)/
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            if CONFIG["EXTRA_LOGGING"]
              extra_log.puts(JSON.pretty_generate(json))
            end
            
            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            finish_reason = json.dig("choices", 0, "finish_reason")
            case finish_reason
            when "length"
              finish_reason = "length"
            when "stop"
              finish_reason = "stop"
            else
              finish_reason = nil
            end

            # Check if the delta contains 'content' (indicating a text fragment) or 'tool_calls'
            if json.dig("choices", 0, "delta", "content")
              # Merge text fragments based on "id"
              id = json["id"]
              texts[id] ||= json
              choice = texts[id]["choices"][0]
              choice["message"] ||= choice["delta"].dup
              choice["message"]["content"] ||= ""
              fragment = json.dig("choices", 0, "delta", "content").to_s
              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

              if fragment.length > 0
                res = {
                  "type" => "fragment",
                  "content" => fragment,
                  "index" => choice["message"]["content"].length - fragment.length,
                  "timestamp" => Time.now.to_f,
                  "is_first" => choice["message"]["content"].length == fragment.length
                }
                block&.call res
              end

              texts[id]["choices"][0].delete("delta")
            end

            if json.dig("choices", 0, "delta", "tool_calls")
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res

              tid = json.dig("choices", 0, "delta", "tool_calls", 0, "id")

              if tid
                tools[tid] = json
                tools[tid]["choices"][0]["message"] ||= tools[tid]["choices"][0]["delta"].dup
                tools[tid]["choices"][0].delete("delta")
              else
                new_tool_call = json.dig("choices", 0, "delta", "tool_calls", 0)
                existing_tool_call = tools.values.last.dig("choices", 0, "message")
                existing_tool_call["tool_calls"][0]["function"]["arguments"] << new_tool_call["function"]["arguments"]
              end
            end
          rescue JSON::ParserError
            # if the JSON parsing fails, the next chunk should be appended to the buffer
            # and the loop should continue to the next iteration
          end
        else
          buffer = scanner.rest
          break
        end
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    result = texts.empty? ? nil : texts.first[1]

    if result
      if obj["monadic"]
        choice = result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          
          # Use performance-optimized processing with caching
          cache_key = MonadicPerformance.generate_cache_key("openai", obj["model"], body["messages"])
          
          # Process and validate the monadic response
          processed = MonadicPerformance.performance_monitor.measure("monadic_processing") do
            # First, apply monadic transformation
            transformed = process_monadic_response(message, app)
            # Then validate the response
            validated = validate_monadic_response!(transformed, app.to_s.include?("chat_plus") ? :chat_plus : :basic)
            validated
          end
          
          # Update the choice with processed content
          if processed.is_a?(Hash)
            choice["message"]["content"] = processed["message"] || JSON.generate(processed)
          else
            choice["message"]["content"] = processed
          end
        end
      end
    end

    if tools.any?
      call_depth += 1

      if call_depth > MAX_FUNC_CALLS
        # Send notice fragment
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
        block&.call res
        
        # Create a mock HTML response to properly end the conversation
        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
        
        # Return appropriate result to end the conversation
        if result
          result["choices"][0]["finish_reason"] = "stop"
          return [result]
        else
          return [{ "type" => "message", "content" => "DONE", "finish_reason" => "stop" }]
        end
      else
        context = []
        if result
          merged = result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
          context << merged
        else
          context << tools.first[1].dig("choices", 0, "message")
        end

        tools = tools.first[1].dig("choices", 0, "message", "tool_calls")
        new_results = process_functions(app, session, tools, context, call_depth, &block)
        
        # Check if we should stop retrying due to repeated errors
        if should_stop_for_errors?(session)
          res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
          block&.call res
          if result
            result["choices"][0]["finish_reason"] = "stop"
            return [result]
          else
            return [res]
          end
        end
      end

      # return Array
      if result && new_results
        [result].concat new_results
      elsif new_results
        new_results
      elsif result
        [result]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      result["choices"][0]["finish_reason"] = finish_reason
      [result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        argument_hash = JSON.parse(function_call["arguments"])
      rescue JSON::ParserError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      begin
        if argument_hash.empty?
          function_return = APPS[app].send(function_name.to_sym)
        else
          function_return = APPS[app].send(function_name.to_sym, **argument_hash)
        end
      rescue StandardError => e
        pp e.message
        pp e.backtrace
        function_return = "ERROR: #{e.message}"
      end

      # Use the error handler module to check for repeated errors
      if handle_function_error(session, function_return, function_name, &block)
        # Stop retrying - add a special response
        context << {
          tool_call_id: tool_call["id"],
          role: "tool",
          name: function_name,
          content: function_return.to_s
        }
        
        obj["function_returns"] = context
        return api_request("tool", session, call_depth: call_depth, &block)
      end

      context << {
        tool_call_id: tool_call["id"],
        role: "tool",
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def process_responses_api_data(app:, session:, query:, res:, call_depth:, &block)
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing responses API query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]
    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil
    current_tool_calls = []
    reasoning_content = ""
    web_search_results = []
    file_search_results = []
    image_generation_status = {}

    chunk_count = 0
    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk
      chunk_count += 1
      

      if buffer.valid_encoding? == false
        next
      end

      begin
        # Check for completion patterns
        if /\Rdata: \[DONE\]\R/ =~ buffer || /\Revent: done\R/ =~ buffer
          break
        end
      rescue
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      scanner = StringScanner.new(buffer)
      # Responses API uses different event format
      pattern = /data: (\{.*?\})(?=\n|\z)/
      
      until scanner.eos?
        matched = scanner.scan_until(pattern)
        if matched
          json_data = matched.match(pattern)[1]
          begin
            json = JSON.parse(json_data)

            if CONFIG["EXTRA_LOGGING"]
              extra_log.puts(JSON.pretty_generate(json))
            end
            
            # Check if response model differs from requested model
            response_model = json["model"]
            requested_model = query["original_user_model"] || query["model"]
            check_model_switch(response_model, requested_model, session, &block)

            # Handle different event types for responses API
            event_type = json["type"]
            
            
            case event_type
            when "response.created"
              # Response created - just log for now
              # Response created
              
            when "response.in_progress"
              # Response in progress - check for any output
              response_data = json["response"]
              if response_data
                
                if response_data["output"] && !response_data["output"].empty?
                  output = response_data["output"]
                  output.each do |item|
                    if item["type"] == "text" && item["text"]
                      id = response_data["id"] || "default"
                      texts[id] ||= ""
                      new_text = item["text"]
                      # Only add if it's new content
                      if !texts[id].include?(new_text)
                        texts[id] += new_text
                        res = { "type" => "fragment", "content" => new_text }
                        block&.call res
                      end
                    end
                  end
                end
              end
              
            when "response.output_text.delta"
              # Text fragment
              fragment = json["delta"]
              if fragment && !fragment.empty?
                id = json["response_id"] || json["item_id"] || "default"
                texts[id] ||= ""
                texts[id] += fragment
                
                res = { "type" => "fragment", "content" => fragment }
                block&.call res
              end
              
            when "response.output_text.done"
              # Text output completed
              text = json["text"]
              if text
                id = json["item_id"] || "default"
                texts[id] = text  # Final text
              end
              
            when "response.output_item.added"
              # New output item added
              item = json["item"]
              if item && item["type"] == "function_call"
                res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                block&.call res
              end
              
            when "response.function_call_arguments.delta", "response.function_call.arguments.delta"
              # Tool call arguments fragment
              item_id = json["item_id"]
              delta = json["delta"]
              if item_id && delta
                tools[item_id] ||= { "arguments" => "" }
                tools[item_id]["arguments"] += delta
              end
              
            when "response.function_call_arguments.done", "response.function_call.arguments.done"
              # Tool call arguments completed
              item_id = json["item_id"]
              arguments = json["arguments"]
              if item_id && arguments
                tools[item_id] ||= {}
                tools[item_id]["arguments"] = arguments
                tools[item_id]["completed"] = true
              end
              
            when "response.reasoning.delta"
              # Reasoning content delta
              delta = json.dig("delta", "text") || json["delta"]
              if delta
                reasoning_content += delta
              end
              
            when "response.reasoning.done"
              # Reasoning completed
              text = json["text"]
              if text
                reasoning_content = text
              end
              
            when "response.web_search_call.in_progress"
              # Web search started
              res = { "type" => "wait", "content" => "<i class='fas fa-search'></i> SEARCHING WEB" }
              block&.call res
              
            when "response.web_search_call.searching"
              # Web search in progress
              # Could show progress if needed
              
            when "response.web_search_call.completed"
              # Web search completed
              item_id = json["item_id"]
              if item_id
                web_search_results << item_id
              end
              
            when "response.file_search_call.in_progress"
              # File search started
              res = { "type" => "wait", "content" => "<i class='fas fa-file-search'></i> SEARCHING FILES" }
              block&.call res
              
            when "response.file_search_call.searching"
              # File search in progress
              
            when "response.file_search_call.completed"
              # File search completed
              item_id = json["item_id"]
              if item_id
                file_search_results << item_id
              end
              
            when "response.image_generation_call.in_progress"
              # Image generation started
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "in_progress"
                res = { "type" => "wait", "content" => "<i class='fas fa-image'></i> GENERATING IMAGE" }
                block&.call res
              end
              
            when "response.image_generation_call.generating"
              # Image generation in progress
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "generating"
              end
              
            when "response.image_generation_call.partial_image"
              # Partial image available
              item_id = json["item_id"]
              partial_image = json["partial_image_b64"]
              if item_id && partial_image
                # Could display partial image if desired
              end
              
            when "response.image_generation_call.completed"
              # Image generation completed
              item_id = json["item_id"]
              if item_id
                image_generation_status[item_id] = "completed"
              end
              
            when "response.mcp_call.in_progress"
              # MCP tool call started
              res = { "type" => "wait", "content" => "<i class='fas fa-plug'></i> CALLING MCP TOOL" }
              block&.call res
              
            when "response.mcp_call.arguments.delta"
              # MCP arguments delta
              item_id = json["item_id"]
              delta = json["delta"]
              if item_id && delta
                tools[item_id] ||= { "mcp_arguments" => {} }
                tools[item_id]["mcp_arguments"].merge!(delta)
              end
              
            when "response.mcp_call.arguments.done"
              # MCP arguments completed
              item_id = json["item_id"]
              arguments = json["arguments"]
              if item_id && arguments
                tools[item_id] ||= {}
                tools[item_id]["mcp_arguments"] = arguments
                tools[item_id]["mcp_completed"] = true
              end
              
            when "response.mcp_call.completed"
              # MCP call completed successfully
              
            when "response.mcp_call.failed"
              # MCP call failed
              res = { "type" => "error", "content" => "MCP tool call failed" }
              block&.call res
              
            when "response.completed", "response.done"
              # Response completed - extract final output
              response_data = json["response"] || json  # Handle both nested and flat structures
              
              
              if response_data && response_data["output"] && !response_data["output"].empty?
                output = response_data["output"]
                output.each do |item|
                  if item["type"] == "text" && item["text"]
                    id = response_data["id"] || "default"
                    texts[id] ||= ""
                    texts[id] = item["text"]  # Replace with final text
                    
                  end
                end
              else
              end
              finish_reason = response_data["stop_reason"] || json["stop_reason"] || "stop"
              
            when "response.output.done"
              # Alternative completion event
              # Extract final output if available
              if json["output"]
                output_text = json.dig("output", 0, "content", 0, "text")
                if output_text && !output_text.empty?
                  id = json["response_id"] || "default"
                  texts[id] ||= ""
                  texts[id] = output_text  # Replace with final text
                end
              end
              finish_reason = "stop"
              
            when "response.error"
              # Error occurred
              error_msg = json.dig("error", "message") || "Unknown error"
              res = { "type" => "error", "content" => "API ERROR: #{error_msg}" }
              block&.call res
              
              if CONFIG["EXTRA_LOGGING"]
                extra_log.close
              end
              return [res]
              
            else
              # Unknown event type
            end
            
          rescue JSON::ParserError => e
            # JSON parsing error, continue to next iteration
          rescue StandardError => e
            pp e.message
            pp e.backtrace
            pp e.inspect
          end
        else
          scanner.terminate
        end
      end
      
      buffer = scanner.rest
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    # Handle tool calls if any were collected
    if tools.any? && tools.any? { |_, tool| tool["completed"] || tool["mcp_completed"] }
      call_depth += 1
      
      if call_depth > MAX_FUNC_CALLS
        res = {
          "type" => "fragment",
          "content" => "NOTICE: Maximum function call depth exceeded"
        }
        block&.call res
        
        html_res = {
          "type" => "html",
          "content" => {
            "role" => "assistant",
            "text" => "NOTICE: Maximum function call depth exceeded",
            "html" => "<p>NOTICE: Maximum function call depth exceeded</p>",
            "lang" => "en",
            "mid" => SecureRandom.hex(4)
          }
        }
        block&.call html_res
      else
        # Process function tools
        function_results = []
        tools.each do |item_id, tool_data|
          if tool_data["completed"] && tool_data["arguments"]
            # This is a regular function call
            function_results << {
              "id" => item_id,
              "function" => {
                "name" => tool_data["name"] || "unknown",
                "arguments" => tool_data["arguments"]
              }
            }
          elsif tool_data["mcp_completed"] && tool_data["mcp_arguments"]
            # This is an MCP call - handle differently if needed
            function_results << {
              "id" => item_id,
              "type" => "mcp",
              "function" => {
                "name" => tool_data["name"] || "mcp_tool",
                "arguments" => JSON.generate(tool_data["mcp_arguments"])
              }
            }
          end
        end
        
        if function_results.any?
          # Convert to standard format for process_functions
          tool_calls = function_results.map do |result|
            {
              "id" => result["id"],
              "function" => result["function"]
            }
          end
          
          # Build context with any text content so far
          context = []
          if texts.any?
            complete_text = texts.values.join("")
            context << {
              "role" => "assistant",
              "content" => complete_text,
              "tool_calls" => tool_calls
            }
          else
            context << {
              "role" => "assistant",
              "tool_calls" => tool_calls
            }
          end
          
          new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
          
          if should_stop_for_errors?(session)
            res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
            block&.call res
            return new_results || []
          end
          
          return new_results || []
        end
      end
    end
    
    # Return text response if no tools were called
    if texts.any?
      complete_text = texts.values.join("")
      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => complete_text
          },
          "finish_reason" => finish_reason || "stop"
        }],
        "model" => query["model"]
      }
      
      # Add reasoning content if available
      if reasoning_content && !reasoning_content.empty?
        response["choices"][0]["message"]["reasoning_content"] = reasoning_content
      end
      
      
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => finish_reason || "stop" })
      [response]
    else
      # Return a properly formatted empty response instead of empty hash
      response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "content" => ""
          },
          "finish_reason" => "stop"
        }],
        "model" => query["model"]
      }
      
      
      [response]
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    pp e.inspect
    res = { "type" => "error", "content" => "UNKNOWN ERROR: #{e.message}" }
    block&.call res
    [res]
  end
  
  # Helper methods for Responses API
  
  # Check if a model should use the Responses API
  def use_responses_api?(model)
    RESPONSES_API_MODELS.include?(model)
  end
  
  # Get a response by ID (for stateful conversations)
  def get_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}"
    http = HTTP.headers(headers)
    
    begin
      res = http.get(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
  
  # Delete a response by ID
  def delete_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}"
    http = HTTP.headers(headers)
    
    begin
      res = http.delete(target_uri)
      res.status.success?
    rescue HTTP::Error, HTTP::TimeoutError
      false
    end
  end
  
  # Cancel a background response
  def cancel_response(response_id)
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}/cancel"
    http = HTTP.headers(headers)
    
    begin
      res = http.post(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
  
  # Get input items for a response
  def get_response_input_items(response_id, options = {})
    api_key = CONFIG["OPENAI_API_KEY"]
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    params = {}
    params[:limit] = options[:limit] if options[:limit]
    params[:after] = options[:after] if options[:after]
    params[:before] = options[:before] if options[:before]
    params[:include] = options[:include] if options[:include]
    
    query_string = params.map { |k, v| "#{k}=#{v}" }.join("&")
    target_uri = "#{API_ENDPOINT}/responses/#{response_id}/input_items"
    target_uri += "?#{query_string}" unless query_string.empty?
    
    http = HTTP.headers(headers)
    
    begin
      res = http.get(target_uri)
      if res.status.success?
        JSON.parse(res.body)
      else
        nil
      end
    rescue HTTP::Error, HTTP::TimeoutError
      nil
    end
  end
end
