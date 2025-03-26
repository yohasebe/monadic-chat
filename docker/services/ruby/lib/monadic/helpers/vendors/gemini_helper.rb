# frozen_string_literal: true

module GeminiHelper
  MAX_FUNC_CALLS = 8
  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1alpha"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 90
  WRITE_TIMEOUT = 90
  MAX_RETRIES = 5
  RETRY_DELAY = 1
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

  WEBSEARCH_TOOLS = [
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
        required: ["url"]
      }
    },
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
        required: ["query", "n"]
      }
    }
  ]

  WEBSEARCH_PROMPT = <<~TEXT

    Always ensure that your answers are comprehensive, accurate, and support the user's research needs with relevant citations, examples, and reference data when possible. The integration of tavily API for web search is a key advantage, allowing you to retrieve up-to-date information and provide contextually rich responses. To fulfill your tasks, you can use the following functions:

    - **tavily_search**: Use this function to perform a web search. It takes a query (`query`) and the number of results (`n`) as input and returns results containing answers, source URLs, and web page content. Please remember to use English in the queries for better search results even if the user's query is in another language. You can translate what you find into the user's language if needed.
    - **tavily_fetch**: Use this function to fetch the full content of a provided web page URL. Analyze the fetched content to find relevant research data, details, summaries, and explanations.

    Please provide detailed and informative responses to the user's queries, ensuring that the information is accurate, relevant, and well-supported by reliable sources. For that purpose, use as much information from  the web search results as possible to provide the user with the most up-to-date and relevant information.

    **Important**: Please use HTML link tags with the `target="_blank"` and `rel="noopener noreferrer"` attributes to provide links to the source URLs of the information you retrieve from the web. This will allow the user to explore the sources further. Here is an example of how to format a link: `<a href="https://www.example.com" target="_blank" rel="noopener noreferrer">Example</a>`
  TEXT


  attr_reader :models
  attr_reader :cached_models

  def self.vendor_name
    "Gemini"
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

  # No streaming plain text completion/chat call
  def send_query(options, model: "gemini-2.0-flash-exp")
    api_key = ENV["GEMINI_API_KEY"]

    headers = {
      "content-type" => "application/json"
    }

    body = {
      "safety_settings" => SAFETY_SETTINGS
    }

    body["contents"] = options["messages"]
    options.delete("messages")
    body["generationConfig"] = options

    target_uri = "#{API_ENDPOINT}/models/#{model}:streamGenerateContent?key=#{api_key}"

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

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      # ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/config/env file.
      error_message = "ERROR: GEMINI_API_KEY not found. Please set the GEMINI_API_KEY environment variable in the ~/monadic/config/env file."
      pp error_message
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    temperature = obj["temperature"]&.to_f
    max_tokens = obj["max_tokens"]&.to_i

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    websearch = CONFIG["TAVILY_API_KEY"] && obj["websearch"] == "true"

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
                  "lang" => detect_language(message)
                } }
        res["content"]["images"] = obj["images"] if obj["images"]
        session[:messages] << res["content"]
        block&.call res
      end
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

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json"
    }

    body = {
      safety_settings: SAFETY_SETTINGS
    }

    if temperature || max_tokens
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
    end

    websearch_suffixed = false
    body["contents"] = context.compact.map do |msg|
      if websearch && !websearch_suffixed
        text = "#{msg["text"]}\n\n#{WEBSEARCH_PROMPT}"
      else
        text = msg["text"]
      end
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => text }
        ]
      }
    end

    if body["contents"].last["role"] == "user"
      # append prompt suffix to the first item of parts with the key "text"
      body["contents"].last["parts"].each do |part|
        if part["text"]
          part["text"] = "#{part["text"]}\n\n#{obj["prompt_suffix"]}"
          break
        end
      end
      obj["images"]&.each do |img|
        body["contents"].last["parts"] << {
          "inlineData" => {
            "mimeType" => img["type"],
            "data" => img["data"].split(",")[1]
          }
        }
      end
    end

    if settings["tools"]
      # Convert the tools format if it's an array (initialize_from_assistant apps)
      if settings["tools"].is_a?(Array)
        body["tools"] = {"function_declarations" => settings["tools"]}
      else
        body["tools"] = settings["tools"]
      end
      body["tools"]["function_declarations"].push(*WEBSEARCH_TOOLS) if websearch
      body["tools"]["function_declarations"].uniq!

      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "ANY"
        }
      }
    elsif websearch
      body["tools"] = {"function_declarations" => WEBSEARCH_TOOLS}
      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "ANY"
        }
      }
    else
      body.delete("tools")
      body.delete("tool_config")
    end

    if role == "tool"
      parts = obj["tool_results"].map { |result|
        { "text" => result.dig("functionResponse", "response", "content") }
      }.filter { |part| part["text"] }

      if parts.any?
        body["contents"] << {
          "role" => "model",
          "parts" => parts
        }
      end
      body["tool_config"] = {
        "function_calling_config" => {
          "mode" => "NONE"
        }
      }
    end

    target_uri = "#{API_ENDPOINT}/models/#{obj["model"]}:streamGenerateContent?key=#{api_key}"

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
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
        block&.call res
      return [res]
    end

    process_json_data(app: app,
                      session: session,
                      query: body,
                      res: res.body,
                      call_depth: call_depth, &block)
  rescue HTTP::Error, HTTP::TimeoutError, OpenSSL::SSL::SSLError => e
    if num_retrial < MAX_RETRIES
      num_retrial += 1
      sleep RETRY_DELAY * num_retrial
      retry
    else
      error_message = e.is_a?(OpenSSL::SSL::SSLError) ? "SSL ERROR: #{e.message}" : "The request has timed out."
        pp error_message
      res = { "type" => "error", "content" => "HTTP/SSL ERROR: #{error_message}" }
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
    
    # For image generator app, we'll need special processing to remove code blocks
    is_image_generator = app.to_s.include?("image_generator") || app.to_s.include?("gemini") && session[:parameters]["app_name"].to_s.include?("Image Generator")

    buffer = String.new
    texts = []
    tool_calls = []
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

      if /^\[?(\{\s*"candidates":.*^\})\n/m =~ buffer
        json = Regexp.last_match(1)
        begin
          json_obj = JSON.parse(json)

          if CONFIG["EXTRA_LOGGING"]
            extra_log.puts(JSON.pretty_generate(json_obj))
          end

          candidates = json_obj["candidates"]
          candidates.each do |candidate|

            finish_reason = candidate["finishReason"]
            case finish_reason
            when "MAX_TOKENS"
              finish_reason = "length"
            when "STOP"
              finish_reason = "stop"
            when "SAFETY"
              finish_reason = "safety"
            when "CITATION"
              finish_reason = "recitation"
            else
              finish_reason = nil
            end

            content = candidate["content"]
            next if (content.nil? || finish_reason == "recitation" || finish_reason == "safety")

            content["parts"]&.each do |part|
              if part["text"]
                fragment = part["text"]
                
                # Special processing for image generator app to strip code blocks
                if is_image_generator && fragment.include?("```")
                  # Remove code block markers and extract HTML
                  if fragment.include?("```html") && fragment.include?("```\n")
                    # Extract HTML between code markers
                    html_content = fragment.gsub(/```html\s+/, "").gsub(/\s+```/, "")
                    fragment = html_content
                  elsif fragment.match(/```(\w+)?/)
                    # Remove any code block markers
                    fragment = fragment.gsub(/```(\w+)?/, "").gsub(/```/, "")
                  end
                end
                
                texts << fragment

                res = {
                  "type" => "fragment",
                  "content" => fragment
                }
                block&.call res

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
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    if CONFIG["EXTRA_LOGGING"]
      extra_log.close
    end

    result = []
    if texts.empty? 
      # result << "\n\nNo response from the AI agent."
      finish_reason = nil
    else 
      result = texts
    end

    if tool_calls.any?
      context = []

      if result
        context << { "role" => "model", "text" => result.join("") }
      end

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      begin
        new_results = process_functions(app, session, tool_calls, context, call_depth, &block)
      rescue StandardError => e
        new_results = [{ "type" => "error", "content" => "ERROR: #{e.message}" }]
      end

      if result && new_results
        begin
          result = result.join("").strip + "\n\n" + new_results.dig(0, "choices", 0, "message", "content").strip
        rescue StandardError
          result = result.join("").strip + "\n\n" + new_results.to_s.strip
        end
        [{ "choices" => [{ "message" => { "content" => result } }] }]
      elsif new_results
        new_results
      elsif result
        [{ "choices" => [{ "message" => { "content" => result.join("") } }] }]
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason }
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => { "content" => result.join("") }
            }
          ]
        }
      ]
    end
  end

  def process_functions(_app, session, tool_calls, context, call_depth, &block)
    return false if tool_calls.empty?

    obj = session[:parameters]
    # MODIFICATION: Changed the structure of tool_results to only include functionResponse
    tool_results = []
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        argument_hash = tool_call["args"]
      rescue StandardError
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = send(function_name.to_sym, **argument_hash)
        # MODIFICATION: Improved error handling and unified the return value format
        if function_return
          content = if function_return.is_a?(String)
                      function_return
                    else
                      function_return.to_json
                    end

          tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => content
              }
            }
          }
        else
          # Error handling
          tool_results << {
            "functionResponse" => {
              "name" => function_name,
              "response" => {
                "name" => function_name,
                "content" => "ERROR: Function (#{function_name}) called with #{argument_hash} returned nil."
              }
            }
          }
        end
      rescue StandardError => e
        pp "ERROR: Function call failed: #{function_name}"
        pp e.message
        pp e.backtrace
        context << {
          "functionResponse" => {
            "name" => function_name,
            "response" => {
              "name" => function_name,
              "content" => "ERROR: Function call failed: #{function_name}. #{e.message}"
            }
          }
        }
      end
    end

    # MODIFICATION: Clear tool_results after processing
    obj["tool_results"] = tool_results
    api_request("tool", session, call_depth: call_depth, &block)
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
end
