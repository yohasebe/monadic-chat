module ClaudeHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5 * 2
  READ_TIMEOUT = 60 * 2
  WRITE_TIMEOUT = 60 * 2
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  MIN_PROMPT_CACHING = 1024
  MAX_PC_PROMPTS = 4

  # websearch tools
  WEBSEARCH_TOOLS = [
    {
      name: "tavily_fetch",
      description: "fetch the content of the web page of the given url and return its content.",
      input_schema: {
        type: "object",
        properties: {
          url: {
            type: "string",
            description: "url of the web page."
          }
        },
        required: ["url"],
      }
    },
    {
      name: "tavily_search",
      description: "search the web for the given query and return the result. the result contains the answer to the query, the source url, and the content of the web page.",
      input_schema: {
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
      }
    }
  ]

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`

    When mentioning specific facts, statistics, references, proper names, or other data, ensure that your information is accurate and up-to-date. Use `tavily_search` to verify the information and provide the user with the most reliable and recent data available. Use `tavily_fetch` to retrieve the full content of a web page URL and analyze it for relevant information. When showing your response based on the web search results, include the source URLs and relevant content from the web pages to support your answers.
  TEXT


  attr_accessor :thinking

  class << self
    attr_reader :cached_models

    def vendor_name
      "Anthropic"
    end

    def list_models
      # Return cached models if they exist
      return $MODELS[:anthropic] if $MODELS[:anthropic]

      api_key = CONFIG["ANTHROPIC_API_KEY"]
      return [] if api_key.nil?

      headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01"
      }

      target_uri = "#{API_ENDPOINT}/models"
      http = HTTP.headers(headers)

      begin
        res = http.get(target_uri)

        if res.status.success?
          # Cache the model list
          model_data = JSON.parse(res.body)
          $MODELS[:anthropic] = model_data["data"].map do |model|
            model["id"]
          end.select do |model|
            !model.include?("claude-2")
          end
          $MODELS[:anthropic]
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      $MODELS[:anthropic] = nil
    end
  end

  def initialize
    @leftover = []
    @thinking = []
    super
  end

  def add_replacements(result)
    result.strip!
    replacements = {
      "<thinking>" => "<div data-title='Thinking' class='toggle'><div class='toggle-open'>",
      "</thinking>" => "</div></div>",
      "<search_quality_reflection>" => "<div data-title='Search Quality Reflection' class='toggle'><div class='toggle-open'>",
      "</search_quality_reflection>" => "</div></div>",
      "<search_quality_score>" => "<div data-title='Search Quality Score' class='toggle'><div class='toggle-open'>",
      "</search_quality_score>" => "</div></div>",
      "<result>" => "",
      "</result>" => ""
    }

    replacements.each do |old, new|
      result = result.gsub(/#{old}\n?/m) { new }
    end

    result
  end

  # No streaming plain text completion/chat call
  def send_query(options, model: "claude-3-5-sonnet-20241022")
    api_key = ENV["ANTHROPIC_API_KEY"]

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "x-api-key" => api_key,
    }

    # Set the body for the API request
    body = {
      "model" => model,
      "stream" => false,
      "messages" => []
    }

    body.merge!(options)
    target_uri = "#{API_ENDPOINT}/messages"
    http = HTTP.headers(headers)

    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      # Check that res exists and has a successful status.
      break if res && res.status && res.status.success?

      sleep RETRY_DELAY
    end

    if res && res.status && res.status.success?
      begin
        # Parse response only once in the success case.
        parsed_response = JSON.parse(res.body)
        return parsed_response.dig("choices", 0, "message", "content")
      rescue JSON::ParserError => e
        return "ERROR: Failed to parse response JSON: #{e.message}"
      end
    else
      error_response = nil
      begin
        # Attempt to parse the error body only once.
        error_response = (res && res.body) ? JSON.parse(res.body) : { "error" => "No response received" }
      rescue JSON::ParserError => e
        error_response = { "error" => "Failed to parse error response JSON: #{e.message}" }
      end
      pp error_response
      return "ERROR: #{error_response["error"]}"
    end
  rescue StandardError => e
    return "Error: The request could not be completed. (#{e.message})"
  end

  def get_thinking_text(result)
    @thinking += result.scan(%r{<thinking>.*?</thinking>}m) if result
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["ANTHROPIC_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: ANTHROPIC_API_KEY not found.  Please set the ANTHROPIC_API_KEY environment variable in the ~/monadic/config/env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    system_prompts = []
    session[:messages].each_with_index do |msg, i|
      next unless msg["role"] == "system"

      if obj["prompt_caching"] && i < MAX_PC_PROMPTS
        check_num_tokens(msg) if obj["prompt_caching"]
      end

      if system_prompts.empty?
        text = msg["text"] + "\n---\n" + WEBSEARCH_PROMPT
      else
        text = msg["text"]
      end

      sp = { type: "text", text: text }
      if obj["prompt_caching"] && msg["tokens"]
        sp["cache_control"] = { "type" => "ephemeral" }
      end

      system_prompts << sp
    end

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"

    if role != "tool"
      # Apply monadic transformation if monadic mode is enabled
      if obj["monadic"].to_s == "true" && message != ""
        if message != ""
          APPS[app].methods
          message = APPS[app].monadic_unit(message)
        end
      end
    end

    if message != "" && role == "user"
      @thinking.clear
      res = { "type" => "user",
              "content" => {
                "role" => role,
                "mid" => request_id,
                "text" => obj["message"],
                "html" => markdown_to_html(message),
                "lang" => detect_language(obj["message"]),
                "active" => true
              } }

      res["content"]["images"] = obj["images"] if obj["images"]
      block&.call res
      session[:messages] << res["content"]
    end

    # Set old messages in the session to inactive
    # and add active messages to the context
    begin
      session[:messages].each { |msg| msg["active"] = false }

      context = session[:messages].filter do |msg|
        msg["role"] == "user" || msg["role"] == "assistant"
      end.last(context_size).each { |msg| msg["active"] = true }

      session[:messages].filter do |msg|
        msg["role"] == "system"
      end.each { |msg| msg["active"] = true }
    rescue StandardError
      context = []
    end

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json",
      "anthropic-version" => "2023-06-01",
      "anthropic-beta" => "prompt-caching-2024-07-31,pdfs-2024-09-25",
      "anthropic-dangerous-direct-browser-access": "true",
      "x-api-key" => api_key,
    }

    # Set the body for the API request
    body = {
      "system" => system_prompts,
      "model" => obj["model"],
      "stream" => true,
      "tool_choice" => {
        "type": "any"
      }
    }

    body["temperature"] = temperature if temperature
    body["max_tokens"] = max_tokens if max_tokens

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings["tools"]
      body["tools"].push(*WEBSEARCH_TOOLS) if websearch
      body["tools"].uniq!
    elsif websearch
      body["tools"] = WEBSEARCH_TOOLS
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # Add the context to the body
    messages = context.compact.map do |msg|
      content = { "type" => "text", "text" => msg["text"] }
      { "role" => msg["role"], "content" => [content] }
    end

    if messages.empty?
      messages << {
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "Hello."
          }
        ]
      }
    end

    if !messages.empty? && messages.last["role"] == "user"
      content = messages.last["content"]

      # Handle PDFs and images if present
      if obj["images"]
        obj["images"].each do |file|
          if file["type"] == "application/pdf"
            doc = {
              "type" => "document",
              "source" => {
                "type" => "base64",
                "media_type" => "application/pdf",
                "data" => file["data"].split(",")[1]
              }
            }
            doc["cache_control"] = { "type" => "ephemeral" } if obj["prompt_caching"]
            content.unshift(doc)
          else
            # Handle images
            img = {
              "type" => "image",
              "source" => {
                "type" => "base64",
                "media_type" => file["type"],
                "data" => file["data"].split(",")[1]
              }
            }
            img["cache_control"] = { "type" => "ephemeral" } if obj["prompt_caching"]
            content << img
          end
        end
      end
    end

    body["messages"] = messages

    if role == "tool"
      body["messages"] += obj["function_returns"]
      @leftover += obj["function_returns"]
      body["tool_choice"] = { "type" => "auto" }
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/messages"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

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
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    process_json_data(app, session, res.body, call_depth, &block)
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

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]
    buffer = String.new
    texts = []
    tool_calls = []
    finish_reason = nil

    content_type = "text"

    body.each do |chunk|
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

            # Handle content type changes
            new_content_type = json.dig("content_block", "type")
            if new_content_type == "tool_use"
              json["content_block"]["input"] = ""
              tool_calls << json["content_block"]
            end
            content_type = new_content_type if new_content_type

            if content_type == "tool_use"
              if json.dig("delta", "partial_json")
                fragment = json.dig("delta", "partial_json").to_s
                next if !fragment || fragment == ""

                tool_calls.last["input"] << fragment
              end
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "tool_use"
                  #fragment = <<~FRAG

                  #<div class='toggle'><pre>
                  #  #{JSON.pretty_generate(tool_calls.last)}
                  #</pre></div>

                  #FRAG

                  #texts << fragment

                  finish_reason = "tool_use"
                  res1 = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                  block&.call res1
                end
              end
            else
              # Handle text content
              if json.dig("delta", "text")
                fragment = json.dig("delta", "text").to_s
                next if !fragment || fragment == ""

                texts << fragment

                res = {
                  "type" => "fragment",
                  "content" => fragment
                }
                block&.call res
              end

              # Handle stop reasons
              if json.dig("delta", "stop_reason")
                stop_reason = json.dig("delta", "stop_reason")
                case stop_reason
                when "max_tokens"
                  finish_reason = "length"
                when "end_turn"
                  finish_reason = "stop"
                end
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

    # Combine all text fragments
    result = if texts.empty?
               nil
             else
               texts.join("")
             end

    # Process tool calls if any exist
    if tool_calls.any?
      get_thinking_text(result)

      call_depth += 1

      # Check for maximum function call depth
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      # Process each tool call individually
      responses = tool_calls.map do |tool_call|
        context = []
        context << {
          "role" => "assistant",
          "content" => []
        }

        # Add the current result to context if it exists
        if result
          context.last["content"] << {
            "type" => "text",
            "text" => result
          }
        end

        # Parse tool call input
        begin
          input_hash = JSON.parse(tool_call["input"])
        rescue JSON::ParserError
          input_hash = {}
        end

        tool_call["input"] = input_hash
        context.last["content"] << {
          "type" => "tool_use",
          "id" => tool_call["id"],
          "name" => tool_call["name"],
          "input" => tool_call["input"]
        }

        # Process single tool call
        process_functions(app, session, [tool_call], context, call_depth, &block)
      end

      # Return the last response
      responses.last

      # Process regular text response
    elsif result
      # Handle different model types
      case session[:parameters]["model"]
      when /opus/
        result = add_replacements(result)
        result = add_replacements(@thinking.join("\n")) + result
        result = result.gsub(%r{<thinking>.*?</thinking>}m, "")
      when /sonnet/
        unless @leftover.empty?
          leftover_assistant = @leftover.filter { |x| x["role"] == "assistant" }
          result = leftover_assistant.map { |x| x.dig("content", 0, "text") }.join("\n") + result
        end
      end
      @leftover.clear

      # Apply monadic transformation if enabled
      if result && obj["monadic"]
        begin
          # Check if result is valid JSON
          JSON.parse(result)
          # If it's already JSON, apply monadic_map directly
          result = APPS[app].monadic_map(result)
        rescue JSON::ParserError
          # If not JSON, wrap it in the proper format before applying monadic_map
          wrapped = JSON.pretty_generate({
            "message" => result,
            "context" => {}
          })
          result = APPS[app].monadic_map(wrapped)
        end
      end

      # Send completion message
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res

      # Return final response
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result }
            }
          ]
        }
      ]
    end
  end

  def check_num_tokens(msg)
    t = msg["tokens"]
    if t
      new_t = t.to_i
    else
      new_t = MonadicApp::TOKENIZER.count_tokens(msg["text"]).to_i
      msg["tokens"] = new_t
    end
    new_t > MIN_PROMPT_CACHING
  end

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]
    tools.each do |tool_call|
      tool_name = tool_call["name"]

      begin
        argument_hash = tool_call["input"]
      rescue StandardError
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      # wait for the app instance is ready up to 10 seconds
      app_instance = APPS[app]

      if argument_hash.empty?
        tool_return = app_instance.send(tool_name.to_sym)
      else
        tool_return = app_instance.send(tool_name.to_sym, **argument_hash)
      end

      unless tool_return
        tool_return = "Empty result"
      end

      content << {
        type: "tool_result",
        tool_use_id: tool_call["id"],
        content: tool_return.to_s
      }
    end

    context << {
      role: "user",
      content: content
    }

    obj["function_returns"] = context

    # Return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def monadic_unit(message)
    begin
      # If message is already JSON, parse and reconstruct
      json = JSON.parse(message)
      res = {
        "message" => json["message"] || message,
        "context" => json["context"] || @context
      }
    rescue JSON::ParserError
      # If not JSON, create the structure
      res = {
        "message" => message,
        "context" => @context
      }
    end
    res.to_json
  end

  def monadic_map(monad)
    begin
      obj = monadic_unwrap(monad)
      # Process the message part
      message = obj["message"].is_a?(String) ? obj["message"] : obj["message"].to_s
      # Update context if block is given
      @context = block_given? ? yield(obj["context"]) : obj["context"]
      # Create the result structure
      result = {
        "message" => message,
        "context" => @context
      }
      JSON.pretty_generate(sanitize_data(result))
    rescue JSON::ParserError
      # Handle invalid JSON input
      result = {
        "message" => monad.to_s,
        "context" => @context
      }
      JSON.pretty_generate(sanitize_data(result))
    end
  end

  def monadic_unwrap(monad)
    JSON.parse(monad)
  rescue JSON::ParserError
    { "message" => monad.to_s, "context" => @context }
  end

  def sanitize_data(data)
    if data.is_a? String
      return data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    if data.is_a? Hash
      data.each do |key, value|
        data[key] = sanitize_data(value)
      end
    elsif data.is_a? Array
      data.map! do |value|
        sanitize_data(value)
      end
    end

    data
  end
end
