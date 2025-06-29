# frozen_string_literal: true

require_relative "../../utils/interaction_utils"

module PerplexityHelper
  include InteractionUtils
  MAX_FUNC_CALLS = 20
  API_ENDPOINT = "https://api.perplexity.ai"

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60 * 10
  WRITE_TIMEOUT = 60 * 10

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  attr_reader :models

  def self.vendor_name
    "Perplexity"
  end

  def self.list_models
    ["sonar",
     "sonar-pro",
     "sonar-reasoning",
     "sonar-reasoning-pro",
     "sonar-deep-research",
     "r1-1776"
    ]
  end

  # Simple non-streaming chat completion
  def send_query(options, model: "sonar-pro")
    # Convert symbol keys to string keys to support both formats
    options = options.transform_keys(&:to_s) if options.is_a?(Hash)
    
    # Get API key
    api_key = CONFIG["PERPLEXITY_API_KEY"]
    return "Error: PERPLEXITY_API_KEY not found" if api_key.nil?
    
    # Set headers
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
    
    # Special handling for AI User requests (similar to Claude)
    if options["ai_user_system_message"] 
      # For AI User, create a simplified sequence that works reliably
      simple_messages = [
        # First, always start with a user message (required by Perplexity)
        {
          "role" => "user",
          "content" => "I need you to respond as if you were the user in a conversation."
        },
        # Then add an assistant message
        {
          "role" => "assistant", 
          "content" => "I understand. I'll simulate natural user responses based on the conversation context."
        },
        # Finally add another user message with instructions (this ensures last message is user)
        {
          "role" => "user",
          "content" => "Based on this conversation context: \"#{options["ai_user_system_message"]}\", provide a natural response as if you were the user. Keep it conversational and authentic."
        }
      ]
      
      # Prepare simple request body
      body = {
        "model" => model,
        "max_tokens" => options["max_tokens"] || 1000,
        "temperature" => options["temperature"] || 0.7,
        "messages" => simple_messages
      }
      
      # Make API request directly
      target_uri = "#{API_ENDPOINT}/chat/completions"
      http = HTTP.headers(headers)
      
      response = nil
      MAX_RETRIES.times do
        begin
          response = http.timeout(
            connect: OPEN_TIMEOUT,
            write: WRITE_TIMEOUT,
            read: READ_TIMEOUT
          ).post(target_uri, json: body)
          
          break if response && response.status && response.status.success?
        rescue StandardError
          # Continue to next retry
        end
        
        sleep RETRY_DELAY
      end
      
      # Process response
      if response && response.status && response.status.success?
        begin
          parsed_response = JSON.parse(response.body)
          return parsed_response.dig("choices", 0, "message", "content") || "Error: No content in response"
        rescue => e
          return "Error: #{e.message}"
        end
      else
        begin
          error_data = response && response.body ? JSON.parse(response.body) : {}
          error_message = error_data.dig("error", "message") || error_data["error"] || "Unknown error"
          return "Error: #{error_message}"
        rescue => e
          return "Error: Failed to parse error response"
        end
      end
      
      return "Error: Failed to get AI User response"
    end
    
    # Regular non-AI User conversation processing
    messages = []
    
    if options["messages"]
      # First, collect all messages with valid content
      valid_msgs = options["messages"].map do |msg|
        content = msg["content"] || msg["text"] || ""
        next if content.to_s.strip.empty?
        
        # Normalize roles to either "user" or "assistant"
        role = case msg["role"].to_s.downcase
               when "user" then "user"
               when "assistant" then "assistant"
               when "system" then "system"
               else "user"  # Default other roles to user
               end
        
        {"role" => role, "content" => content.to_s}
      end.compact

      # Handle system message specially
      system_msgs = valid_msgs.select { |m| m["role"] == "system" }
      conversation_msgs = valid_msgs.reject { |m| m["role"] == "system" }
      
      # Add system messages first if any
      messages.concat(system_msgs) if system_msgs.any?
      
      # Force strictly alternating user/assistant pattern
      if conversation_msgs.any?
        # Start with user message
        if conversation_msgs.first["role"] != "user"
          # Add a synthetic user message if needed
          messages << {
            "role" => "user",
            "content" => "Let's continue our conversation."
          }
        end
        
        # Build properly alternating sequence
        expected_role = "user"
        conversation_msgs.each do |msg|
          if msg["role"] == expected_role
            messages << msg
            # Toggle role for next message
            expected_role = expected_role == "user" ? "assistant" : "user"
          end
        end
        
        # CRITICAL: Always ensure we end with a user message - required by Perplexity API
        if messages.empty?
          # If no messages at all, add a default user message
          messages << {
            "role" => "user",
            "content" => "Hello, I'd like to have a conversation."
          }
        elsif messages.last["role"] != "user"
          # If last message is not from user, add a user message
          messages << {
            "role" => "user",
            "content" => "How would you respond to this conversation?"
          }
        end
      elsif messages.empty?
        # Add a default user message if no valid messages
        messages << {
          "role" => "user",
          "content" => "Hello, I'd like to have a conversation."
        }
      end
    end
    
    # Prepare request body
    body = {
      "model" => model,
      "max_tokens" => options["max_tokens"] || 1000,
      "temperature" => options["temperature"] || 0.7,
      "messages" => messages
    }
    
    # Make request
    target_uri = "#{API_ENDPOINT}/chat/completions"
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
      rescue StandardError
        # Continue to next retry
      end
      
      sleep RETRY_DELAY
    end
    
    # Process response
    if response && response.status && response.status.success?
      begin
        parsed_response = JSON.parse(response.body)
        return parsed_response.dig("choices", 0, "message", "content") || "Error: No content in response"
      rescue => e
        return "Error: #{e.message}"
      end
    else
      begin
        error_data = response && response.body ? JSON.parse(response.body) : {}
        error_message = error_data.dig("error", "message") || error_data["error"] || "Unknown error"
        return "Error: #{error_message}"
      rescue => e
        return "Error: Failed to parse error response"
      end
    end
  rescue => e
    return "Error: #{e.message}"
  end

  # Connect to OpenAI API and get a response
  def api_request(role, session, call_depth: 0, &block)
    
    # Set the number of times the request has been retried to 0
    num_retrial = 0

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]
    api_key = CONFIG["PERPLEXITY_API_KEY"]
    
    
    unless api_key && !api_key.empty?
      error_message = "ERROR: PERPLEXITY_API_KEY not found or empty"
      pp error_message
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return [res]
    end
    
    # Process the API request

    # Get the parameters from the session
    initial_prompt = if session[:messages].empty?
                       obj["initial_prompt"]
                     else
                       session[:messages].first["text"]
                     end

    prompt_suffix = obj["prompt_suffix"]
    model = obj["model"]
    

    max_tokens = obj["max_tokens"]&.to_i 
    temperature = obj["temperature"]&.to_f
    presence_penalty = obj["presence_penalty"]&.to_f
    frequency_penalty = obj["frequency_penalty"]&.to_f 
    frequency_penalty = 1.0 if frequency_penalty == 0.0

    context_size = obj["context_size"]&.to_i

    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

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

      html = markdown_to_html(obj["message"], mathjax: obj["mathjax"])

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
    session[:messages].each { |msg| msg["active"] = false }
    
    # Safer context building with nil checks - this was causing the error
    context = []
    
    # Only add first message if it exists
    if session[:messages] && session[:messages].first
      context << session[:messages].first
    end
    
    # Add remaining messages if they exist, with safe navigation
    if session[:messages] && session[:messages].length > 1 && context_size && context_size > 0
      # Use safe array access with a range that won't go out of bounds
      remaining = session[:messages][1..-1]
      if remaining && !remaining.empty?
        # Get last N messages based on context_size
        last_n = remaining.last([context_size, remaining.length].min)
        context += last_n if last_n
      end
    end
    
    # Mark all context messages as active
    context.each { |msg| msg["active"] = true if msg }
    
    # Context is ready for API request

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
    }

    body["stream"] = true
    body["n"] = 1

    body["temperature"] = temperature if temperature
    body["presence_penalty"] = presence_penalty if presence_penalty
    body["frequency_penalty"] = frequency_penalty if frequency_penalty
    body["max_tokens"] = max_tokens if max_tokens

    # Perplexity supports json_schema format for structured outputs
    if obj["response_format"]
      body["response_format"] = APPS[app].settings["response_format"]
    end

    # For monadic apps, we need to provide a proper JSON schema
    if obj["monadic"] || obj["json"]
      # Define the JSON schema for Chat Plus response
      chat_plus_schema = {
        "type" => "json_schema",
        "json_schema" => {
          "schema" => {
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
                    "items" => {
                      "type" => "string"
                    },
                    "description" => "A list of topics discussed in the conversation"
                  },
                  "people" => {
                    "type" => "array",
                    "items" => {
                      "type" => "string"
                    },
                    "description" => "A list of people and their relationships mentioned"
                  },
                  "notes" => {
                    "type" => "array",
                    "items" => {
                      "type" => "string"
                    },
                    "description" => "Important information to remember"
                  }
                },
                "required" => ["reasoning", "topics", "people", "notes"]
              }
            },
            "required" => ["message", "context"]
          }
        }
      }
      body["response_format"] ||= chat_plus_schema
    end

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
      body["tool_choice"] = "auto"
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # The context is added to the body
    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [{ "type" => "text", "text" => msg["text"] }] }
      if msg["images"] && role == "user"
        msg["images"].each do |img|
          messages_containing_img = true
          message["content"] << {
            "type" => "image_url",
            "image_url" => {
              "url" => img["data"],
              "detail" => "high"
            }
          }
        end
      end
      message
    end
    
    # If no messages in context, add initial system message
    if body["messages"].empty? && initial_prompt
      body["messages"] << {
        "role" => "system",
        "content" => [{ "type" => "text", "text" => initial_prompt }]
      }
    end
    
    # Get the roles in the message list
    roles = body["messages"].map { |msg| msg["role"] }
    
    # Case 1: If only system message exists (initiate_from_assistant=true at the start)
    if body["messages"].length == 1 && body["messages"][0]["role"] == "system"
      body["messages"] << {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => "Let's start" }]
      }
    # Case 2: If there's a system message followed by an assistant message
    # (This happens on second turn when the inserted user message is lost)
    elsif roles.length >= 2 && 
          roles[0] == "system" && roles.find_index("assistant") &&
          roles.find_index("assistant") > 0 &&
          roles[0...roles.find_index("assistant")].all? { |r| r == "system" }
      
      # Find the first assistant message
      assistant_index = roles.find_index("assistant")
      
      # Insert user message right before the first assistant message
      body["messages"].insert(assistant_index, {
        "role" => "user",
        "content" => [{ "type" => "text", "text" => "Let's start" }]
      })
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
      body["tool_choice"] = "auto"
    end

    # Check if this is a reasoning model (includes "reasoning" or starts with r followed by digits)
    if obj["model"].include?("reasoning") || obj["model"].match?(/^r\d+/)
      body.delete("temperature")
      body.delete("tool_choice")
      body.delete("tools")
      body.delete("presence_penalty")
      body.delete("frequency_penalty")

      # remove the text from the beginning of the message to "---" from the previous messages
      body["messages"] = body["messages"].each do |msg|
        msg["content"].each do |item|
          if item["type"] == "text"
            item["text"] = item["text"].sub(/---\n\n/, "")
          end
        end
      end
    else
      if obj["monadic"] || obj["json"]
        body["response_format"] ||= { "type" => "json_object" }
      end
    end

    last_text = context.last&.dig("text") || ""

    # Decorate the last message in the context with the message with the snippet
    # and the prompt suffix
    last_text = message_with_snippet if message_with_snippet.to_s != ""

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

    # Perplexity models support images natively, no need to switch models
    if messages_containing_img
      body.delete("stop")
    end

    # Request body is ready
    
    # Send initial spinner message
    res = { "type" => "wait", "content" => "<i class='fas fa-spinner fa-pulse'></i> THINKING" }
    block&.call res
    
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
      begin
        error_data = JSON.parse(res.body) rescue { "message" => res.body.to_s, "status" => res.status }
        formatted_error = format_api_error(error_data, "perplexity")
        res = { "type" => "error", "content" => "API ERROR: #{formatted_error}" }
        block&.call res
        return [res]
      rescue StandardError
        res = { "type" => "error", "content" => "API ERROR: Unknown error occurred" }
        block&.call res
        return [res]
      end
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

  def check_citations(text, citations)
    # Return early if citations is nil or empty
    return [text, []] if citations.nil? || citations.empty?
    
    used_citations = text.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq.sort

    citation_map = used_citations.each_with_index.to_h { |old_num, index| [old_num, index + 1] }

    newtext = text.gsub(/\[(\d+)\]/) do |match|
      "[#{citation_map[$1.to_i]}]"
    end

    new_citations = if used_citations && used_citations.any?
                      used_citations.compact.map { |i| citations[i - 1] }.compact
                    else
                      []
                    end

    [newtext, new_citations]
  end

  def process_json_data(app:, session:, query:, res:, call_depth:, &block)
    
    if CONFIG["EXTRA_LOGGING"]
      extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
      extra_log.puts("Processing query at #{Time.now} (Call depth: #{call_depth})")
      extra_log.puts(JSON.pretty_generate(query))
    end

    obj = session[:parameters]

    buffer = String.new
    texts = {}
    thinking = []
    tools = {}
    finish_reason = nil
    started = false
    current_json = nil
    stopped = false
    json = nil

    res.each do |chunk|
      chunk = chunk.force_encoding("UTF-8")
      buffer << chunk

      if buffer.valid_encoding? == false
        next
      end

      buffer.encode!("UTF-16", "UTF-8", invalid: :replace, replace: "")
      buffer.encode!("UTF-8", "UTF-16")

      first_iteration = true


      while (match = buffer.match(/^data: (\{.*?\})\r\n/m))
        json_str = match[1]
        buffer = buffer[match[0].length..-1]

        begin
          json = JSON.parse(json_str)

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts(JSON.pretty_generate(json))
          end

          finish_reason = json.dig("choices", 0, "finish_reason")
          delta = json.dig("choices", 0, "delta")

          if delta && delta["content"]
            id = json["id"]
            texts[id] ||= json
            choice = texts[id]["choices"][0]
            choice["message"] ||= delta.dup
            choice["message"]["content"] ||= ""

            fragment = delta["content"].to_s
            choice["message"]["content"] << fragment

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
          elsif delta && delta["tool_calls"]
            res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
            block&.call res

            tid = delta["tool_calls"][0]["id"]
            if tid
              tools[tid] = json
              tools[tid]["choices"][0]["message"] ||= tools[tid]["choices"][0]["delta"].dup
              tools[tid]["choices"][0].delete("delta")
            end
          end

          # This comment-out is due to the lack of finish_reason in the JSON response from "sonar-pro"
          if json["choices"][0]["finish_reason"] == "stop"
            # Debug logging to trace the entire process
            if CONFIG["EXTRA_LOGGING"]
              DebugHelper.debug("Perplexity: Processing finish_reason=stop for model #{obj["model"]}", category: :api, level: :info)
              if texts.first && texts.first[1]
                content_preview = texts.first[1]["choices"][0]["message"]["content"][0..100] rescue ""
                DebugHelper.debug("Perplexity: Content before processing: #{content_preview}...", category: :api, level: :debug)
              end
            end
            
            # Only process <think> tags for reasoning models
            if obj["model"].include?("reasoning") || obj["model"].match?(/^r\d+/)
              if CONFIG["EXTRA_LOGGING"]
                DebugHelper.debug("Perplexity: Extracting thinking blocks for reasoning model", category: :api, level: :info)
              end
              
              original_content = texts.first[1]["choices"][0]["message"]["content"]
              
              # Check if there are citations in the original content before processing
              citation_refs_before = original_content.scan(/\[(\d+)\]/).flatten
              if CONFIG["EXTRA_LOGGING"] && citation_refs_before.any?
                DebugHelper.debug("Perplexity: Citation references found before thinking removal: #{citation_refs_before}", category: :api, level: :info)
              end
              
              # Extract citation references from thinking blocks to preserve them
              preserved_citations = []
              processed_content = original_content.gsub(/<think>(.*?)<\/think>\s*/m) do
                think_content = $1
                thinking << think_content
                
                # Extract any citation references from the thinking block
                think_citations = think_content.scan(/\[(\d+)\]/)
                if think_citations.any?
                  preserved_citations.concat(think_citations.flatten)
                  if CONFIG["EXTRA_LOGGING"]
                    DebugHelper.debug("Perplexity: Found citations in thinking block: #{think_citations.flatten}", category: :api, level: :debug)
                  end
                end
                
                "" # Remove the thinking block
              end
              
              # Check if citations were lost during thinking removal
              citation_refs_after = processed_content.scan(/\[(\d+)\]/).flatten
              if CONFIG["EXTRA_LOGGING"]
                if citation_refs_before.any? || citation_refs_after.any? || preserved_citations.any?
                  DebugHelper.debug("Perplexity: Citations - before: #{citation_refs_before}, after: #{citation_refs_after}, in thinking: #{preserved_citations}", category: :api, level: :info)
                end
              end
              
              texts.first[1]["choices"][0]["message"]["content"] = processed_content
              
              if CONFIG["EXTRA_LOGGING"]
                DebugHelper.debug("Perplexity: Thinking blocks extracted: #{thinking.size}", category: :api, level: :info)
                DebugHelper.debug("Perplexity: Content after thinking removal: #{processed_content[0..100] rescue ""}...", category: :api, level: :debug)
              end
            end

            # Skip citations processing for monadic mode
            if !obj["monadic"]
              citations = json["citations"] if json["citations"]
              
              # Debug: Check citations for all models
              if CONFIG["EXTRA_LOGGING"]
                DebugHelper.debug("Perplexity: Model #{obj["model"]} - citations present: #{!citations.nil?}, count: #{citations&.size || 0}", category: :api, level: :info)
                if citations && citations.any?
                  DebugHelper.debug("Perplexity: Citations content: #{citations.inspect}", category: :api, level: :debug)
                end
                # Check if content has citation references
                content = texts.first[1]["choices"][0]["message"]["content"]
                citation_refs = content.scan(/\[(\d+)\]/).flatten
                if citation_refs.any?
                  DebugHelper.debug("Perplexity: Found citation references in content: #{citation_refs}", category: :api, level: :info)
                end
              end
              
              new_text, new_citations = check_citations(texts.first[1]["choices"][0]["message"]["content"], citations)
              
              # Debug: Log citation processing results
              if CONFIG["EXTRA_LOGGING"]
                DebugHelper.debug("Perplexity: After check_citations - new_citations count: #{new_citations&.size || 0}", category: :api, level: :info)
                if new_text != texts.first[1]["choices"][0]["message"]["content"]
                  DebugHelper.debug("Perplexity: Citation references were renumbered", category: :api, level: :debug)
                end
              end
              
              # add citations to the last message
              if citations && citations.any?
                citation_text = "\n\n<div data-title='Citations' class='toggle'><ol>" + new_citations.map.with_index do |citation, i|
                  "<li><a href='#{citation}' target='_blank' rel='noopener noreferrer'>#{CGI.unescape(citation)}</a></li>"
                end.join("\n") + "</ol></div>"
                
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("Perplexity: Adding citation HTML to content", category: :api, level: :info)
                  DebugHelper.debug("Perplexity: Citation HTML preview: #{citation_text[0..100]}...", category: :api, level: :debug)
                end
                
                texts.first[1]["choices"][0]["message"]["content"] = new_text + citation_text
              else
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("Perplexity: No citations to add (citations nil or empty)", category: :api, level: :info)
                end
              end
            else
              if CONFIG["EXTRA_LOGGING"]
                DebugHelper.debug("Perplexity: Skipping citations for monadic mode", category: :api, level: :info)
              end
            end
            stopped = true
            break
          end

        rescue JSON::ParserError => e
          pp "JSON parse error: #{e.message}"
          buffer = "data: #{json_str}" + buffer
          break
        end
      end
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    if json && !stopped
      stopped = true
      
      # Get citations from the response
      citations = json["citations"] if json["citations"]
      
      # Skip citations processing for monadic mode
      if !obj["monadic"]
        # Debug: Log second citation processing
        if CONFIG["EXTRA_LOGGING"]
          DebugHelper.debug("Perplexity: Second citation processing - citations present: #{!citations.nil?}, count: #{citations&.size || 0}", category: :api, level: :info)
        end
        
        new_text, new_citations = check_citations(texts.first[1]["choices"][0]["message"]["content"], citations)
        # add citations to the last message
        if citations && citations.any?
          citation_text = "\n\n<div data-title='Citations' class='toggle'><ol>" + new_citations.map.with_index do |citation, i|
            "<li><a href='#{citation}' target='_blank' rel='noopener noreferrer'>#{CGI.unescape(citation)}</a></li>"
          end.join("\n") + "</ol></div>"
          texts.first[1]["choices"][0]["message"]["content"] = new_text + citation_text
          
          if CONFIG["EXTRA_LOGGING"]
            DebugHelper.debug("Perplexity: Second citation processing - added citations to content", category: :api, level: :info)
          end
        end
      else
        if CONFIG["EXTRA_LOGGING"]
          DebugHelper.debug("Perplexity: Processing citations for monadic mode", category: :api, level: :info)
        end
        
        # For monadic mode, we need to store citations separately
        # They will be processed after JSON parsing
        if citations && citations.any? && texts.first && texts.first[1]
          # Store citations in a temporary location
          texts.first[1]["__citations__"] = citations
        end
      end
    end

    thinking_result = thinking.empty? ? nil : thinking.join("\n\n")
    text_result = texts.empty? ? nil : texts.first[1]
    
    # Store citations in text_result if available
    if text_result && json && json["citations"] && json["citations"].any? && obj["monadic"]
      text_result["__citations__"] = json["citations"]
    end

    if text_result && obj["monadic"]
      # For monadic mode, fix Perplexity's malformed JSON structure
      content = text_result["choices"][0]["message"]["content"]
      
      # Perplexity returns a malformed JSON structure like: {"{"message":"...
      # We need to extract the actual JSON starting from the second {
      if content.start_with?('{"{"') || content.start_with?("{'{\"")
        
        # Find the start of the actual JSON (second opening brace)
        actual_json_start = content.index('{', 1)
        if actual_json_start
          # Extract from the second { to the end
          actual_json = content[actual_json_start..-1]
          
          # Find the matching closing brace for the actual JSON
          # Count braces to find the correct closing position
          brace_count = 0
          last_valid_pos = -1
          
          actual_json.each_char.with_index do |char, idx|
            if char == '{'
              brace_count += 1
            elsif char == '}'
              brace_count -= 1
              if brace_count == 0
                last_valid_pos = idx
                break
              end
            end
          end
          
          if last_valid_pos > -1
            actual_json = actual_json[0..last_valid_pos]
            
            begin
              parsed = JSON.parse(actual_json)
              if parsed.is_a?(Hash) && parsed.key?("message") && parsed.key?("context")
                # Process citations if they exist
                if text_result["__citations__"]
                  citations = text_result["__citations__"]
                  
                  # Check citations in both message and reasoning fields
                  
                  # Combine message and reasoning to check all citations
                  combined_text = "#{parsed["message"]} #{parsed["context"]["reasoning"]}"
                  
                  # For monadic mode, we need to keep the citation numbers
                  # Extract all used citation numbers from both fields
                  msg_refs = parsed["message"].scan(/\[(\d+)\]/).flatten.map(&:to_i)
                  reason_refs = parsed["context"]["reasoning"].scan(/\[(\d+)\]/).flatten.map(&:to_i) if parsed["context"]["reasoning"]
                  all_refs = (msg_refs + (reason_refs || [])).uniq.sort
                  
                  
                  # Collect the actual citations based on the references
                  new_citations = all_refs.map { |ref| citations[ref - 1] }.compact
                  
                  
                  # Don't modify the text - keep the citation numbers as-is
                  parsed["message"] = parsed["message"]
                  parsed["context"]["reasoning"] = parsed["context"]["reasoning"] if parsed["context"]["reasoning"]
                  
                  # Add citations to context
                  parsed["context"]["citations"] = new_citations if new_citations && new_citations.any?
                  
                  # Remove temporary citation storage
                  text_result.delete("__citations__")
                end
                
                # Generate the final JSON with citations included
                final_json = JSON.generate(parsed)
                text_result["choices"][0]["message"]["content"] = final_json
                
              end
            rescue JSON::ParserError => e
              # Failed to parse extracted JSON
            end
          end
        end
      else
        # Try to parse as normal JSON
        begin
          parsed = JSON.parse(content)
          if parsed.is_a?(Hash) && parsed.key?("message") && parsed.key?("context")
            
            # Process citations if they exist
            if text_result["__citations__"]
              citations = text_result["__citations__"]
              
              # Check citations in both message and reasoning fields
              
              # Combine message and reasoning to check all citations
              combined_text = "#{parsed["message"]} #{parsed["context"]["reasoning"]}"
              
              # For monadic mode, we need to keep the citation numbers
              # Extract all used citation numbers from both fields
              msg_refs = parsed["message"].scan(/\[(\d+)\]/).flatten.map(&:to_i)
              reason_refs = parsed["context"]["reasoning"].scan(/\[(\d+)\]/).flatten.map(&:to_i) if parsed["context"]["reasoning"]
              all_refs = (msg_refs + (reason_refs || [])).uniq.sort
              
              
              # Collect the actual citations based on the references
              new_citations = all_refs.map { |ref| citations[ref - 1] }.compact
              
              
              # Don't modify the text - keep the citation numbers as-is
              parsed["message"] = parsed["message"]
              parsed["context"]["reasoning"] = parsed["context"]["reasoning"] if parsed["context"]["reasoning"]
              
              # Add citations to context
              parsed["context"]["citations"] = new_citations if new_citations && new_citations.any?
              
              # Update the content with modified JSON
              text_result["choices"][0]["message"]["content"] = JSON.generate(parsed)
              
              # Remove temporary citation storage
              text_result.delete("__citations__")
            end
          end
        rescue JSON::ParserError => e
          # Content is not valid JSON
        end
      end
    end

    if tools.any?
      context = []
      if text_result
        merged = text_result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
        context << merged
      else
        context << tools.first[1].dig("choices", 0, "message")
      end

      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tools, context, call_depth, &block)

      if text_result && new_results
        [text_result].concat new_results
      elsif new_results
        new_results
      elsif text_result
        [text_result]
      end
    elsif text_result
      text_result["choices"][0]["finish_reason"] = finish_reason
      text_result["choices"][0]["message"]["thinking"] = thinking_result.strip if thinking_result
      
      # Don't set text field - let WebSocket handler decide which field to use
      # The WebSocket handler will use content field for monadic apps
      
      # Debug final text_result structure
      # Set text field for WebSocket handler - it expects this field
      text_result["choices"][0]["text"] = text_result["choices"][0]["message"]["content"]
      
      
      # Send DONE message after all processing is complete, not before
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      
      [text_result]
    else
      res = { "type" => "message", "content" => "DONE" }
      block&.call res
      [res]
    end
  rescue StandardError => e
    pp "[ERROR] Error in process_json_data: #{e.message}"
    pp "[ERROR] Error class: #{e.class}"
    pp "[ERROR] Backtrace:"
    pp e.backtrace[0..5]
    res = { "type" => "error", "content" => "ERROR: #{e.message}" }
    block&.call res
    [res]
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
        function_return = APPS[app].send(function_name.to_sym, **argument_hash)
      rescue StandardError => e
        pp e.message
        pp e.backtrace
        function_return = "ERROR: #{e.message}"
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
