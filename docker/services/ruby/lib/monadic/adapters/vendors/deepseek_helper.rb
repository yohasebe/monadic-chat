# frozen_string_literal: false

require_relative "../../utils/interaction_utils"
require_relative "../../utils/error_formatter"
require_relative "../../utils/language_config"
require_relative "../../utils/system_defaults"
require_relative "../../utils/model_spec"
require 'strscan'
require 'securerandom'

module DeepSeekHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.deepseek.com"
  BETA_API_ENDPOINT = "https://api.deepseek.com/beta"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 120
  WRITE_TIMEOUT = 120
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  # ENV key for emergency override
  DEEPSEEK_LEGACY_MODE_ENV = "DEEPSEEK_LEGACY_MODE"

  # websearch tools (strict-mode compatible)
  WEBSEARCH_TOOLS = [
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
          additionalProperties: false
        }
      }
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
              description: "number of results to return (default: 3).",
              minimum: 1,
              maximum: 10,
              default: 3
            }
          },
          required: ["query"],
          additionalProperties: false
        }
      }
    }
  ]

  WEBSEARCH_PROMPT = <<~TEXT

    IMPORTANT: You have access to web search functions. You MUST use these functions when users ask questions requiring current information or web research.

    Available functions:
    1. **tavily_search** - Search the web for information
       - Parameters: query (string), n (integer, default 3)
       - Example call: {"name": "tavily_search", "arguments": {"query": "latest AI developments 2025", "n": 5}}
       
    2. **tavily_fetch** - Fetch full content from a specific URL
       - Parameters: url (string)
       - Example call: {"name": "tavily_fetch", "arguments": {"url": "https://example.com/article"}}

    When to use these functions:
    - User asks about current events, news, or recent information
    - User asks about specific people, companies, or organizations  
    - User asks questions requiring factual, up-to-date information
    - You need to verify or update information

    Example function calling pattern:
    User: "What are the latest developments in quantum computing?"
    Assistant: I'll search for the latest information about quantum computing developments.
    [Call tavily_search with query "latest quantum computing developments 2025"]

    Always:
    - Use English in search queries for better results
    - Translate results back to user's language if needed
    - Cite sources using HTML links: <a href="URL" target="_blank" rel="noopener noreferrer">Source</a>
    - Use search results to provide accurate, well-supported responses
  TEXT

  class << self
    attr_reader :cached_models

    def vendor_name
      "DeepSeek"
    end

    # Convert tools to strict mode format
    def convert_to_strict_tools(tools)
      return nil if tools.nil? || tools.empty?
      
      tools.map do |tool|
        # Skip if already has strict property
        if tool.dig(:function, :strict) || tool.dig("function", "strict")
          tool
        else
          # Deep clone the tool
          strict_tool = JSON.parse(JSON.generate(tool))
          
          # Add strict: true
          if strict_tool["function"]
            strict_tool["function"]["strict"] = true
            
            # Ensure parameters meet strict mode requirements
            if strict_tool["function"]["parameters"]
              ensure_strict_schema(strict_tool["function"]["parameters"])
            end
          end
          
          strict_tool
        end
      end
    end
    
    # Recursively ensure schema meets strict mode requirements
    def ensure_strict_schema(schema)
      return unless schema.is_a?(Hash)
      
      if schema["type"] == "object"
        # STRICT MODE REQUIREMENT: All object properties must be required
        schema["additionalProperties"] = false
        
        # Set ALL properties as required (strict mode requirement)
        if schema["properties"]
          schema["required"] = schema["properties"].keys
          
          # Recursively process nested schemas
          schema["properties"].each do |prop_name, prop_schema|
            ensure_strict_schema(prop_schema)
          end
        end
      elsif schema["type"] == "array" && schema["items"]
        # Process array items schema
        ensure_strict_schema(schema["items"])
      elsif schema["anyOf"]
        # Process each alternative schema
        schema["anyOf"].each { |alt_schema| ensure_strict_schema(alt_schema) }
      elsif schema["oneOf"]
        # Process each alternative schema
        schema["oneOf"].each { |alt_schema| ensure_strict_schema(alt_schema) }
      elsif schema["allOf"]
        # Process each combined schema
        schema["allOf"].each { |alt_schema| ensure_strict_schema(alt_schema) }
      end
    end

    # Check if strict mode should be enabled
    def use_strict_mode?(obj)
      # Enable strict mode for deepseek-chat model when function calling is used
      # Can be controlled via configuration or per-request parameter
      model = obj["model"] || DeepSeekHelper.get_default_model
      
      # Check if explicitly disabled
      return false if obj["strict_function_calling"] == false
      
      # Check if explicitly enabled via config
      return true if CONFIG["DEEPSEEK_STRICT_MODE"] == true
      
      # Enable by default for deepseek-chat model
      # NOTE: Special markers like <｜tool▁call▁end｜> are part of the response format
      # and will be cleaned up in the response processing
      return true if model.include?("deepseek-chat")
      
      # Disabled for deepseek-reasoner as it doesn't support function calling
      false
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:deepseek] if $MODELS[:deepseek]

      api_key = CONFIG["DEEPSEEK_API_KEY"]
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
          # Cache the filtered and sorted models
          model_data = JSON.parse(res.body)
          $MODELS[:deepseek] = model_data["data"].sort_by do |model|
            model["created"]
          end.reverse.map do |model|
            model["id"]
          end.filter do |model|
            !model.include?("embed")
          end
          $MODELS[:deepseek]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:deepseek] = nil
    end
  end

  # Get default model
  def self.get_default_model
    "deepseek-chat"
  end

  # Simple non-streaming chat completion
  def send_query(options, model: nil)
    # Use default model from CONFIG if not specified
    model ||= SystemDefaults.get_default_model('deepseek')
    
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["DEEPSEEK_API_KEY"]
    if api_key.nil?
      return Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "DeepSeek",
        env_var: "DEEPSEEK_API_KEY"
      )
    end
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Use the model provided directly - trust default_model_for_provider in AI User Agent
    # Log the model being used
    # Model details are logged to dedicated log files
    
    # Format messages
    messages = []
    
    if options["messages"]
      # Look for system message
      system_msg = options["messages"].find { |m| m["role"] == "system" }
      if system_msg
        messages << {
          "role" => "system",
          "content" => system_msg["content"].to_s
        }
      end
      
      # Process conversation messages
      options["messages"].each do |msg|
        next if msg["role"] == "system" # Skip system (already handled)
        
        content = msg["content"] || msg["text"] || ""
        messages << {
          "role" => msg["role"],
          "content" => content.to_s
        }
      end
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "stream" => false,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages
    }
    
    # Make request
    target_uri = "#{API_ENDPOINT}/chat/completions"
    
    # Debug the full request body
    DebugHelper.debug("DeepSeek API request body: #{JSON.pretty_generate(body)}", category: :api, level: :debug)
    
    http = HTTP.headers(headers)
    
    # Simple retry logic
    response = nil
    MAX_RETRIES.times do
      begin
        response = http.timeout(
          connect: OPEN_TIMEOUT,
          write: WRITE_TIMEOUT,
          read: READ_TIMEOUT
        ).post(target_uri, json: body)
        
        break if response && response.status && response.status.success?
      rescue HTTP::Error, HTTP::TimeoutError
        # Continue to next retry
      end
      
      sleep RETRY_DELAY
    end
    
    # Process response
    if response && response.status && response.status.success?
      begin
        parsed_response = JSON.parse(response.body)
        content = parsed_response.dig("choices", 0, "message", "content")
        return content if content
        
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "DeepSeek",
          message: "No content in response"
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "DeepSeek",
          message: e.message
        )
      end
    else
      begin
        error_data = response && response.body ? JSON.parse(response.body) : {}
        error_message = error_data["error"] || "Unknown error"
        return Monadic::Utils::ErrorFormatter.api_error(
          provider: "DeepSeek",
          message: error_message,
          code: response&.status&.code
        )
      rescue => e
        return Monadic::Utils::ErrorFormatter.parsing_error(
          provider: "DeepSeek",
          message: "Failed to parse error response"
        )
      end
    end
  rescue => e
    return Monadic::Utils::ErrorFormatter.unknown_error(
      provider: "DeepSeek",
      message: e.message
    )
  end

  def api_request(role, session, call_depth: 0, &block)

    num_retrial = 0

    begin
      api_key = CONFIG["DEEPSEEK_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      error_message = Monadic::Utils::ErrorFormatter.api_key_error(
        provider: "DeepSeek",
        env_var: "DEEPSEEK_API_KEY"
      )
      pp error_message
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]

    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    # Handle both string and boolean values for websearch parameter
    websearch = CONFIG["TAVILY_API_KEY"] && (obj["websearch"] == "true" || obj["websearch"] == true)

    if role != "tool"
      message = obj["message"].to_s

      # If the app is monadic, the message is passed through the monadic_map function
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end

      # HTML is generated from the original message, not the monadic version
      html = if obj["message"] != ""
               markdown_to_html(obj["message"])
             else
               obj["message"]
             end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "role" => role,
                  "text" => obj["message"],
                  "html" => markdown_to_html(obj["message"]),
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
        session[:messages] << res["content"]
      end
    end

    session[:messages].each { |msg| msg["active"] = false }
    
    # Safer context building with nil checks
    context = []
    if session[:messages] && !session[:messages].empty?
      context = [session[:messages].first]
      if session[:messages].length > 1
        context += session[:messages][1..].last(context_size + 1)
      end
    end

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # SSOT: supports_streaming gate (default true)
    begin
      spec_stream = Monadic::Utils::ModelSpec.get_model_property(model, "supports_streaming")
      stream_src = spec_stream.nil? ? "fallback" : "spec"
      supports_streaming = spec_stream.nil? ? true : !!spec_stream
    rescue StandardError
      stream_src = "fallback"
      supports_streaming = true
    end
    if ENV[DEEPSEEK_LEGACY_MODE_ENV] == "true"
      supports_streaming = true
      stream_src = "legacy"
    end
    body = {
      "model" => model,
      "stream" => supports_streaming
    }

    body["max_tokens"] = max_tokens if max_tokens

    body["temperature"] = temperature

    system_message_modified = false
    body["messages"] = context.compact.map do |msg|
      if msg["role"] == "system" && !system_message_modified
        system_message_modified = true
        content_parts = [msg["text"]]
        
        # Add language preference if set
        if session[:runtime_settings] && session[:runtime_settings][:language] && session[:runtime_settings][:language] != "auto"
          language_prompt = Monadic::Utils::LanguageConfig.system_prompt_for_language(session[:runtime_settings][:language])
          content_parts << language_prompt if !language_prompt.empty?
        end
        
        # Add websearch prompt if enabled
        content_parts << WEBSEARCH_PROMPT if websearch
        
        { "role" => msg["role"], "content" => content_parts.join("\n\n---\n\n") }
      else
        { "role" => msg["role"], "content" => msg["text"] }
      end
    end

    # Handle initiate_from_assistant case where only system message exists
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      body["messages"] << {
        "role" => "user",
        "content" => "Please proceed according to your system instructions and introduce yourself."
      }
    end

    # Debug app loading
    DebugHelper.debug("DeepSeek app: #{app}, APPS[app] exists: #{!APPS[app].nil?}", category: :api, level: :debug)
    
    # Get tools from app settings
    app_tools = APPS[app] && APPS[app].settings["tools"] ? APPS[app].settings["tools"] : []
    
    # Debug logging
    DebugHelper.debug("DeepSeek app_tools from settings: #{app_tools.inspect}", category: :api, level: :debug)
    DebugHelper.debug("DeepSeek websearch enabled: #{websearch}", category: :api, level: :debug)
    
    # Only include tools if this is not a tool response
    if role != "tool"
      # Build the tools array
      if websearch
        # Always include websearch tools when websearch is enabled
        body["tools"] = WEBSEARCH_TOOLS.dup
        # Add any app-specific tools
        if app_tools && !app_tools.empty?
          body["tools"].concat(app_tools)
          body["tools"].uniq!
        end
        body["tool_choice"] = "auto"
      elsif app_tools && !app_tools.empty?
        # Only app tools, no websearch
        body["tools"] = app_tools
        body["tool_choice"] = "auto"
      else
        # No tools at all - don't send empty array
        body.delete("tools")
        body.delete("tool_choice")
      end
      
      # Apply strict mode if enabled and tools are present
      if body["tools"] && !body["tools"].empty? && DeepSeekHelper.use_strict_mode?(obj)
        DebugHelper.debug("DeepSeek: Enabling strict function calling mode", category: :api, level: :info)
        
        # Convert tools to strict format
        body["tools"] = DeepSeekHelper.convert_to_strict_tools(body["tools"])
        
        # Log the conversion
        if CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
            f.puts "[#{Time.now}] DeepSeek Strict Mode: Converting #{body["tools"].size} tools"
            body["tools"].each do |tool|
              f.puts "  - #{tool.dig("function", "name")}: strict=#{tool.dig("function", "strict")}"
            end
          end
        end
      end
      
      # Debug logging for tools
      if body["tools"]
        DebugHelper.debug("DeepSeek tools configured: #{body["tools"].map { |t| t.dig(:function, :name) || t.dig("function", "name") }.join(", ")}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tool_choice: #{body["tool_choice"]}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek strict mode: #{DeepSeekHelper.use_strict_mode?(obj)}", category: :api, level: :debug)
        DebugHelper.debug("DeepSeek tools full: #{body["tools"].inspect}", category: :api, level: :verbose)
      end
      
      # Final check: ensure tools is not an empty array
      if body["tools"] && body["tools"].empty?
        DebugHelper.debug("DeepSeek: Removing empty tools array", category: :api, level: :debug)
        body.delete("tools")
        body.delete("tool_choice")
      end
    end # end of role != "tool"

    # SSOT: If the model is not tool-capable, remove tools/tool_choice
    begin
      spec_tool = Monadic::Utils::ModelSpec.get_model_property(model, "tool_capability")
      tool_src = spec_tool.nil? ? "fallback" : "spec"
      tool_capable = spec_tool.nil? ? true : !!spec_tool
    rescue StandardError
      tool_src = "fallback"
      tool_capable = true
    end
    if ENV[DEEPSEEK_LEGACY_MODE_ENV] == "true"
      tool_capable = true
      tool_src = "legacy"
    end
    unless tool_capable
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Capability audit (optional)
    if CONFIG["EXTRA_LOGGING"]
      begin
        audit = []
        audit << "streaming:#{supports_streaming}(#{stream_src})"
        audit << "tools:#{tool_capable}(#{tool_src})"
        # Vision/pdf flags (from spec) for reference
        begin
          vprop = Monadic::Utils::ModelSpec.get_model_property(model, "vision_capability")
          vsrc = vprop.nil? ? "fallback" : "spec"
          pprop = Monadic::Utils::ModelSpec.get_model_property(model, "supports_pdf")
          psrc = pprop.nil? ? "fallback" : "spec"
          audit << "vision:#{!!vprop}(#{vsrc})"
          audit << "pdf:#{!!pprop}(#{psrc})"
        rescue
        end
        File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
          f.puts "[#{Time.now}] DeepSeek SSOT capabilities for #{model}: #{audit.join(', ')}"
        end
      rescue
      end
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      body["messages"].last["content"] += "\n\n" + APPS[app].settings["prompt_suffix"] if APPS[app].settings["prompt_suffix"]
    end

    if obj["model"].include?("reasoner")
      body.delete("temperature")
      body.delete("tool_choice")
      body.delete("tools")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].map do |msg|
        msg["content"] = msg["content"].sub(/---\n\n/, "")
        msg
      end
    else
      if obj["monadic"] || obj["json"]
        body["response_format"] ||= { "type" => "json_object" }
      end
    end

    # Use beta endpoint if strict mode is enabled
    use_strict = body["tools"] && !body["tools"].empty? && DeepSeekHelper.use_strict_mode?(obj)
    target_uri = use_strict ? "#{BETA_API_ENDPOINT}/chat/completions" : "#{API_ENDPOINT}/chat/completions"
    headers["Accept"] = "text/event-stream"
    
    if use_strict
      DebugHelper.debug("DeepSeek: Using beta API endpoint for strict function calling", category: :api, level: :info)
    end
    
    # Debug the final API request body
    DebugHelper.debug("DeepSeek streaming API final body: #{JSON.pretty_generate(body)}", category: :api, level: :debug)
    
    # Don't send initial spinner - let the client handle it
    # The spinner will be shown automatically when the request starts
    
    http = HTTP.headers(headers)

    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      if res.status.success?
        break
      end

      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)
      pp error_report
      error_message = Monadic::Utils::ErrorFormatter.api_error(
        provider: "DeepSeek",
        message: error_report.dig("error", "message") || error_report["message"] || "Unknown API error",
        code: res.status.code
      )
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return [res]
    end
    
    # Debug: Log before passing to process_json_data
    if CONFIG["EXTRA_LOGGING"]
      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |log|
        log.puts("Response status: #{res.status}")
        log.puts("Response headers: #{res.headers.to_h}")
        log.puts("About to process streaming response...")
      end
    end

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
                      call_depth: call_depth, &block)
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

    buffer = String.new.force_encoding("UTF-8")
    texts = {}
    tools = {}
    finish_reason = nil

    chunk_count = 0
    res.each do |chunk|
      begin
        chunk_count += 1
        chunk = chunk.force_encoding("UTF-8")
        buffer << chunk
        
        # Debug: Log first few chunks
        if chunk_count <= 3 && CONFIG["EXTRA_LOGGING"]
          extra_log.puts("Chunk #{chunk_count}: #{chunk[0..100]}")
        end

        if buffer.valid_encoding? == false
          next
        end

        # Check for [DONE] message
        begin
          break if /\Rdata: \[DONE\]\R/ =~ buffer
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

              # Process finish reason
              finish_reason = json.dig("choices", 0, "finish_reason")
              DebugHelper.debug("DeepSeek finish_reason: #{finish_reason}", category: :api, level: :verbose) if finish_reason
              
              case finish_reason
              when "length"
                finish_reason = "length"
              when "stop"
                finish_reason = "stop"
              when "tool_calls"
                finish_reason = "function_call"
                DebugHelper.debug("DeepSeek detected tool_calls finish reason", category: :api, level: :debug)
              else
                finish_reason = nil
              end

              # Process text content
              if json.dig("choices", 0, "delta")
                delta = json["choices"][0]["delta"]
                
                if delta["reasoning_content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["reasoning_content"] ||= ""
                  choice["message"]["content"] ||= ""

                  fragment = delta["reasoning_content"].to_s
                  choice["message"]["reasoning_content"] << fragment

                  res = {
                    "type" => "thinking",
                    "content" => fragment
                  }
                  block&.call res

                  texts[id]["choices"][0].delete("delta")
                elsif delta["content"]
                  id = json["id"]
                  texts[id] ||= json
                  choice = texts[id]["choices"][0]
                  choice["message"] ||= delta.dup
                  choice["message"]["content"] ||= ""

                  fragment = delta["content"].to_s
                  choice["message"]["content"] << fragment

                  # Log special markers if detected
                  if fragment =~ /<｜[^｜]+｜>/
                    DebugHelper.debug("DeepSeek special marker detected: #{fragment}", category: :api, level: :info)
                    if CONFIG["EXTRA_LOGGING"]
                      File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
                        f.puts "[#{Time.now}] DeepSeek special marker in fragment: #{fragment}"
                      end
                    end
                  end

                  # Check if DeepSeek is outputting function calls as text
                  if choice["message"]["content"] =~ /```json\s*\n?\s*\{.*"name"\s*:\s*"(tavily_search|tavily_fetch)"/m
                    # DeepSeek is outputting function calls as text, don't send fragments
                    # We'll handle this after the full message is received
                  elsif fragment.length > 0 && !fragment.match?(/<｜[^｜]+｜>/)
                    # Don't send special markers as fragments
                    res = {
                      "type" => "fragment",
                      "content" => fragment,
                      "index" => choice["message"]["content"].length - fragment.length,
                      "timestamp" => Time.now.to_f
                      # Don't send is_first flag to prevent spinner from disappearing
                      # "is_first" => choice["message"]["content"].length == fragment.length
                    }
                    block&.call res
                  end

                  texts[id]["choices"][0].delete("delta")
                end

                # Process tool calls
                if delta["tool_calls"]
                  DebugHelper.debug("DeepSeek tool call detected: #{delta["tool_calls"].inspect}", category: :api, level: :debug)
                  DebugHelper.debug("Full JSON at tool call: #{json.inspect}", category: :api, level: :verbose)
                  
                  res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res

                  tid = json.dig("choices", 0, "delta", "tool_calls", 0, "id")

                  if tid
                    # Clone the json object
                    tools[tid] = JSON.parse(JSON.generate(json))
                    tools[tid]["choices"][0]["message"] ||= {}
                    tools[tid]["choices"][0]["message"]["role"] = "assistant"
                    tools[tid]["choices"][0]["message"]["content"] = ""
                    tools[tid]["choices"][0]["message"]["tool_calls"] ||= []
                    
                    # Copy the tool call info from delta
                    tool_call_delta = json.dig("choices", 0, "delta", "tool_calls", 0)
                    if tool_call_delta
                      new_tool_call = {
                        "id" => tool_call_delta["id"],
                        "type" => tool_call_delta["type"] || "function",
                        "function" => {
                          "name" => tool_call_delta.dig("function", "name") || "",
                          "arguments" => tool_call_delta.dig("function", "arguments") || ""
                        }
                      }
                      tools[tid]["choices"][0]["message"]["tool_calls"] << new_tool_call
                    end
                    
                    tools[tid]["choices"][0].delete("delta")
                  else
                    # Accumulate arguments for existing tool call
                    new_tool_call = json.dig("choices", 0, "delta", "tool_calls", 0)
                    if tools.values.any? && new_tool_call && new_tool_call.dig("function", "arguments")
                      last_tool = tools.values.last
                      if last_tool && last_tool.dig("choices", 0, "message", "tool_calls", 0)
                        last_tool["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"] += new_tool_call["function"]["arguments"]
                      end
                    end
                  end
                end
              end
            rescue JSON::ParserError => e
              pp "JSON parse error: #{e.message}"
            end
          else
            scanner.pos += 1
          end
        end

        buffer = scanner.rest

      rescue StandardError => e
        pp e.message
        pp e.backtrace
        next
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.puts("Total chunks received: #{chunk_count}")
      extra_log.close
    end

    text_result = texts.empty? ? nil : texts.first[1]

    if text_result
      # Remove DeepSeek special markers from content if present
      content = text_result.dig("choices", 0, "message", "content")
      if content
        # Remove special markers like <｜tool▁call▁end｜> and <｜tool▁calls▁end｜>
        content = content.gsub(/<｜[^｜]+｜>/m, "").strip
        text_result["choices"][0]["message"]["content"] = content
        
        if CONFIG["EXTRA_LOGGING"]
          File.open(MonadicApp::EXTRA_LOG_FILE, "a") do |f|
            f.puts "[#{Time.now}] DeepSeek: Cleaned special markers from content"
          end
        end
      end
      
      # Check if DeepSeek has output function calls as text
      if text_result.dig("choices", 0, "message", "content") =~ /```json\s*\n?\s*(\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\})\s*\n?\s*```/m
        json_match = $1
        begin
          # Parse the function call from text
          func_call = JSON.parse(json_match)
          
          # Convert text-based function call to proper tool call format
          if func_call["name"] && func_call["arguments"]
            text_result["choices"][0]["message"]["tool_calls"] = [{
              "id" => "call_#{SecureRandom.hex(8)}",
              "type" => "function",
              "function" => {
                "name" => func_call["name"],
                "arguments" => func_call["arguments"].is_a?(String) ? func_call["arguments"] : JSON.generate(func_call["arguments"])
              }
            }]
            
            # Remove the JSON block from the content
            text_result["choices"][0]["message"]["content"] = text_result["choices"][0]["message"]["content"].gsub(/```json\s*\n?\s*\{.*?"name"\s*:\s*"(tavily_search|tavily_fetch)".*?\}\s*\n?\s*```/m, "").strip
            
            # Set finish reason to function_call
            text_result["choices"][0]["finish_reason"] = "function_call"
            finish_reason = "function_call"
            
            # Add to tools for processing
            tid = text_result["choices"][0]["message"]["tool_calls"][0]["id"]
            tools[tid] = text_result
            
            DebugHelper.debug("DeepSeek: Converted text function call to tool call format", category: :api, level: :debug)
          end
        rescue JSON::ParserError => e
          DebugHelper.debug("DeepSeek: Failed to parse function call from text: #{e.message}", category: :api, level: :debug)
        end
      end
      
      if obj["monadic"]
        choice = text_result["choices"][0]
        if choice["finish_reason"] == "length" || choice["finish_reason"] == "stop"
          message = choice["message"]["content"]
          # monadic_map returns JSON string, but we need the actual content
          modified = APPS[app].monadic_map(message)
          # Parse the JSON and extract the message field
          begin
            parsed = JSON.parse(modified)
            choice["message"]["content"] = parsed["message"] || modified
          rescue JSON::ParserError
            # If parsing fails, use the original modified value
            choice["message"]["content"] = modified
          end
        end
      end
    end

    # If we have tool calls, ignore the finish_reason from streaming
    # as it will be "tool_calls" and we need to wait for the actual completion
    if tools.any?
      finish_reason = nil
    end

    if tools.any?
      # Handle tool/function calls
      DebugHelper.debug("DeepSeek tools before processing: #{tools.inspect}", category: :api, level: :verbose)
      
      tools_data = tools.first[1].dig("choices", 0, "message", "tool_calls")
      
      # If tool_calls is not an array, make it one
      if tools_data && !tools_data.is_a?(Array)
        tools_data = [tools_data]
      end
      
      DebugHelper.debug("DeepSeek tools_data after processing: #{tools_data.inspect}", category: :api, level: :debug)
      
      context = []
      res = {
        "role" => "assistant",
        "content" => "The AI model is calling functions to process the data."
      }
      res["tool_calls"] = tools_data.map do |tool|
        {
          "id" => tool["id"],
          "type" => "function",
          "function" => tool["function"]
        }
      end
      context << res

      # Check for maximum function call depth
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      # Process function calls and get new results - don't send DONE here
      new_results = process_functions(app, session, tools_data, context, call_depth, &block)

      if new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      # Only send DONE when there are no tool calls
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      text_result["choices"][0]["finish_reason"] = finish_reason
      [text_result]
    else
      # Return done message if no result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => "stop" }
      block&.call res
      [res]
    end
  end

  private

  def process_functions(app, session, tools, context, call_depth, &block)
    obj = session[:parameters]
    tools.each do |tool_call|
      function_call = tool_call["function"]
      function_name = function_call["name"]

      begin
        escaped = function_call["arguments"]
        # Handle empty string arguments for tools with no parameters
        if escaped.to_s.strip.empty?
          argument_hash = {}
        else
          argument_hash = JSON.parse(escaped)
        end
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      begin
      if converted.empty?
        function_return = APPS[app].send(function_name.to_sym)
      else
        function_return = APPS[app].send(function_name.to_sym, **converted)
      end
      rescue StandardError => e
        function_return = "ERROR: #{e.message}"
      end

      context << {
        role: "tool",
        tool_call_id: tool_call["id"],
        name: function_name,
        content: function_return.is_a?(Hash) || function_return.is_a?(Array) ? JSON.generate(function_return) : function_return.to_s
      }
    end

    obj["function_returns"] = context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
