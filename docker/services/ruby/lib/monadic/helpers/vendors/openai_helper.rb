# frozen_string_literal: true

module OpenAIHelper
  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.openai.com/v1"
  TEMP_AUDIO_FILE = "temp_audio_file"

  OPEN_TIMEOUT = 20
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60

  MAX_RETRIES = 5
  RETRY_DELAY = 1

  MODELS_N_LATEST = -1

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
    "gpt-4",
    "o1-preview"
  ]

  # partial string match
  REASONING_MODELS = [
    "o3",
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
  NON_STREAM_MODELS = []

  # websearch tools
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

    To fulfill your tasks, you can use the following functions:

    1. **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.

    2. **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`

    When mentioning specific facts, statistics, references, proper names, or other data, ensure that your information is accurate and up-to-date. Use `tavily_search` to verify the information and provide the user with the most reliable and recent data available. Use `tavily_fetch` to retrieve the full content of a web page URL and analyze it for relevant information. When showing your response based on the web search results, include the source URLs and relevant content from the web pages to support your answers.
  TEXT

  class << self
    attr_reader :cached_models

    def vendor_name
      "OpenAI"
    end

    def list_models
      # Return cached models if they exist
      return @cached_models if @cached_models

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
          res_body = JSON.parse(res.body)
          if res_body && res_body["data"]
            # Cache the filtered and sorted models
            @cached_models = res_body["data"].sort_by do |item|
              item["created"]
            end.reverse[0..MODELS_N_LATEST].map do |item|
              item["id"]
              # Filter out excluded models, embedding each string in a regex
            end.reject do |model|
              EXCLUDED_MODELS.any? { |excluded_model| /\b#{excluded_model}\b/ =~ model }
            end
            @cached_models
          end
        end
      rescue HTTP::Error, HTTP::TimeoutError
        []
      end
    end

    # Method to manually clear the cache if needed
    def clear_models_cache
      @cached_models = nil
    end
  end

  # No streaming plain text completion/chat call
  def send_query(options, model: "gpt-4o-mini")
    api_key = ENV["OPENAI_API_KEY"]

    # Set the headers for the API request
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    # Set the body for the API request
    body = {
      "model" => model,
      "n" => 1,
      "stream" => false,
      "stop" => nil,
      "messages" => []
    }

    body.merge!(options)
    target_uri = API_ENDPOINT + "/chat/completions"
    http = HTTP.headers(headers)

    res = nil
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      # Ensure res and its status exist before checking success
      break if res && res.status && res.status.success?

      sleep RETRY_DELAY
    end

    if res && res.status && res.status.success?
      begin
        # Parse response only once in the success branch
        parsed_response = JSON.parse(res.body)
        return parsed_response.dig("choices", 0, "message", "content")
      rescue JSON::ParserError => e
        return "ERROR: Failed to parse response JSON: #{e.message}"
      end
    else
      error_response = nil
      begin
        # Attempt to parse error response body only once
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

    max_completion_tokens = obj["max_completion_tokens"]&.to_i || obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    presence_penalty = obj["presence_penalty"].to_f
    frequency_penalty = obj["frequency_penalty"].to_f
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)
    message_with_snippet = nil

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"

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
    session[:messages].each { |msg| msg["active"] = false }
    context = [session[:messages].first]
    if session[:messages].length > 1
      context += session[:messages][1..].last(context_size)
    end
    context.each { |msg| msg["active"] = true }

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

    if reasoning_model
      body["reasoning_effort"] = reasoning_effort || "medium"
      body.delete("temperature")
      body.delete("frequency_penalty")
      body.delete("presence_penalty")
      body.delete("max_completion_tokens")
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
        body["tools"].append(WEBSEARCH_TOOLS) if websearch
      elsif websearch
        body["tools"] = WEBSEARCH_TOOLS
      else
        body.delete("tools")
        body.delete("tool_choice")
      end
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

    # "system" role must be replaced with "developer" for reasoning models
    if reasoning_model
      num_sysetm_messages = 0
      body["messages"].each do |msg|
        if msg["role"] == "system"
          msg["role"] = "developer" 
          msg["content"].each do |content_item|
            if content_item["type"] == "text" && num_sysetm_messages == 0
              if websearch
                text = "Web search enabled\n---\n" + content_item["text"] + "\n---\n" + WEBSEARCH_PROMPT
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

    last_text = context.last["text"]

    # Split the last message if it matches /\^__DATA__$/
    if last_text.match?(/\^\s*__DATA__\s*$/m)
      last_text, data = last_text.split("__DATA__")
      # set last_text to the last message in the context
      context.last["text"] = last_text
    end

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

    if messages_containing_img
      unless obj["vision_capability"]
        body["model"] = "gpt-4o"
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
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
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
      process_json_data(app, session, res.body, call_depth, &block)
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

  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]
    reasoning_model = REASONING_MODELS.any? { |reasoning_model| /\b#{reasoning_model}\b/ =~ obj["model"] }

    buffer = String.new
    texts = {}
    tools = {}
    finish_reason = nil

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

              # Skip if duplicate fragment is found in the reasoning model
              # if choice["message"]["content"].end_with?(fragment) && reasoning_model
              #   next
              # end

              choice["message"]["content"] << fragment
              next if !fragment || fragment == ""

              res = {
                "type" => "fragment",
                "content" => fragment
              }
              block&.call res

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
      context = []
      if result
        merged = result["choices"][0]["message"].merge(tools.first[1]["choices"][0]["message"])
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
