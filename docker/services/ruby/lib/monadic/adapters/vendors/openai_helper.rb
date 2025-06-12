# frozen_string_literal: true

require 'fileutils'
require 'base64'
require 'securerandom'
require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_pattern_detector"
require_relative "../../utils/function_call_error_handler"
require_relative "../../utils/debug_helper"

module OpenAIHelper
  include InteractionUtils
  include ErrorPatternDetector
  include FunctionCallErrorHandler
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

  # Native OpenAI websearch tools
  NATIVE_WEBSEARCH_TOOLS = [
    {
      type: "function",
      function:
      {
        name: "websearch_agent",
        description: "Search the web for the given query and return the result. The result contains the answer to the query including the source url links",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "query to search for."
            }
          },
          required: ["query"],
          additionalproperties: false
        }
      },
      strict: true
    }
  ]

  # Tavily-based websearch tools
  TAVILY_WEBSEARCH_TOOLS = [
    {
      type: "function",
      function:
      {
        name: "tavily_fetch",
        description: "fetch the content of the web page of the given url and return its content.",
        parameters: {
          type: "object",
          properties: {
            url: {
              type: "string",
              description: "url of the web page."
            }
          },
          required: ["url"],
          additionalproperties: false
        }
      },
      strict: true
    },
    {
      type: "function",
      function:
      {
        name: "tavily_search",
        description: "search the web for the given query and return the result. the result contains the answer to the query, the source url, and the content of the web page.",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "query to search for."
            },
            n: {
              type: "integer",
              description: "number of results to return (default: 3)."
            }
          },
          required: ["query"],
          additionalproperties: false
        }
      },
      strict: true
    }
  ]

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT
  
  NATIVE_WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. To fulfill your tasks, you can use the following function(s):

     **websearch_agent**: Use this function to perform a web search. It takes a query (`query`) as input and returns results containing answers including source URL links.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT

  TAVILY_WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
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
    
    api_key = ENV["OPENAI_API_KEY"] || CONFIG["OPENAI_API_KEY"]
    
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

    # Check if web search is enabled
    websearch = obj["websearch"] == "true"
    
    # Determine which web search implementation to use
    # Search-specific models use native OpenAI search
    native_websearch_models = SEARCH_MODELS
    
    # Check if model supports native web search and native is enabled
    use_native_websearch = websearch && 
                          native_websearch_models.include?(model) &&
                          CONFIG["OPENAI_NATIVE_WEBSEARCH"] != "false"
    
    # Use Tavily if API key is available and native is not being used
    use_tavily_websearch = websearch && 
                          CONFIG["TAVILY_API_KEY"] && 
                          !use_native_websearch
    
    # Store these variables in obj for later use in the method
    obj["use_native_websearch"] = use_native_websearch
    obj["use_tavily_websearch"] = use_tavily_websearch

    message = nil
    data = nil

    if role != "tool"
      message = obj["message"].to_s

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

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
    if websearch && reasoning_model && !search_model
      original_model = model
      model = ENV["WEBSEARCH_MODEL"] || "gpt-4.1-mini"
      body["model"] = model
      
      # Update model flags after switching
      reasoning_model = REASONING_MODELS.any? { |reasoning_model| /\b#{reasoning_model}\b/ =~ model }
      non_stream_model = NON_STREAM_MODELS.any? { |non_stream_model| /\b#{non_stream_model}\b/ =~ model }
      non_tool_model = NON_TOOL_MODELS.any? { |non_tool_model| /\b#{non_tool_model}\b/ =~ model }
      search_model = SEARCH_MODELS.any? { |search_model| /\b#{search_model}\b/ =~ model }
      
      # Add a note about the model switch in the initial prompt
      if context && context.first && context.first["text"]
        context.first["text"] = "[Note: Automatically switched from #{original_model} to #{model} for web search functionality]\n\n" + context.first["text"]
      end
    end
    
    # Determine which prompt to use based on web search type
    websearch_prompt = if obj["use_tavily_websearch"]
                       TAVILY_WEBSEARCH_PROMPT
                     elsif obj["use_native_websearch"]
                       NATIVE_WEBSEARCH_PROMPT
                     else
                       WEBSEARCH_PROMPT
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

      if obj["monadic"] || obj["json"]
        body["response_format"] ||= { "type" => "json_object" }
      end
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
      if obj["tools"] && !obj["tools"].empty?
        body["tools"] = APPS[app].settings["tools"]
        body["tools"] = [] if body["tools"].nil?
        
        # Add appropriate web search tools
        if obj["use_native_websearch"]
          body["tools"].push(*NATIVE_WEBSEARCH_TOOLS)
        elsif obj["use_tavily_websearch"]
          body["tools"].push(*TAVILY_WEBSEARCH_TOOLS)
        end
        
        body["tools"].uniq!
      elsif obj["use_native_websearch"]
        body["tools"] = NATIVE_WEBSEARCH_TOOLS
      elsif obj["use_tavily_websearch"]
        body["tools"] = TAVILY_WEBSEARCH_TOOLS
      else
        body.delete("tools")
        body.delete("tool_choice")
      end
    end

    # The context is added to the body
    messages_containing_img = false
    image_file_references = []
    
    # START ADDED CODE
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
    # END ADDED CODE
    
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
      num_sysetm_messages = 0
      body["messages"].each do |msg|
        if msg["role"] == "system"
          msg["role"] = "developer" 
          msg["content"].each do |content_item|
            if content_item["type"] == "text" && num_sysetm_messages == 0
              if websearch
                text = "Web search enabled\n---\n" + content_item["text"] + "\n---\n" + websearch_prompt
              else
                text = "Formatting re-enabled\n---\n" + content_item["text"]
              end
              content_item["text"] = text
            end
          end
          num_sysetm_messages += 1
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

    # START ADDED CODE
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
    # END ADDED CODE

    if last_text != "" && prompt_suffix.to_s != ""
      new_text = last_text + "\n\n" + prompt_suffix.strip if prompt_suffix.to_s != ""
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
        "content" => data.strip
      }
      body["prediction"] = {
        "type" => "content",
        "content" => data.strip
      }
    end

    # initial prompt in the body is appended with the settings["system_prompt_suffix"
    if initial_prompt != "" && obj["system_prompt_suffix"].to_s != ""
      new_text = initial_prompt + "\n\n" + obj["system_prompt_suffix"].strip
      body["messages"].first["content"].each do |content_item|
        if content_item["type"] == "text"
          content_item["text"] = new_text
        end
      end
    end

    if messages_containing_img
      unless obj["vision_capability"]
        body["model"] = "gpt-4.1"
        body.delete("reasoning_effort")
      end
      body.delete("stop")
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

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

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
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
      frag = obj.dig("choices", 0, "message", "content")
      block&.call({ "type" => "fragment", "content" => frag, "finish_reason" => "stop" })
      block&.call({ "type" => "message", "content" => "DONE", "finish_reason" => "stop" })
      [obj]
    else
      process_json_data(app: app,
                        session: session,
                        query: body,
                        res: res.body,
                        call_depth: call_depth, &block)

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
          modified = APPS[app].monadic_map(message)
          choice["text"] = modified
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
end
