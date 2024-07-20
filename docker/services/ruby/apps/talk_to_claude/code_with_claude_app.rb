class CodeWithClaude < MonadicApp
  include UtilitiesHelper

  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.anthropic.com/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  def icon
    "<i class='fa-solid fa-a'></i>"
  end

  def description
    "This is an application that allows you to run Python code with Anthropic Claude"
  end

  def initial_prompt
    text = <<~TEXT
      You are an assistant designed to help users write and run code and visualize data upon their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze.

      A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment. Use the `fetch_text_from_file` function to fetch the text from the file and return its content. Give the base file name as the parameter to the function.

      If the user's request is too complex, please suggest that the user break it down into smaller parts, suggesting possible next steps.

      If you need to run a Python code, follow the instructions below:

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the `command` name such as `python` or `ruby`, your program `code` to be executed with the command, and the file `extension` with which the code is stored in a temporary local file. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

      If you need to check the availability of a certain file or command in the bash command, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

      If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it.

      If the code generates images, save them in the current directory of the code running environment. Use a descriptive file name without any preceding path for this purpose. When there are multiple image file types available, SVG is preferred.

      If the user asks for it, you can also start a Jupyter Lab server using the `run_jupyter(command)` function. If successful, you should provide the user with the URL to access the Jupyter Lab server in a way that the user can easily click on it and the new tab opens in the browser using `<a href="URL" target="_blank">Jupyter Lab</a>`.
     
      The code contained your function calling command is not directly shown to the user, so please make sure you include the same code to the regular text response inside a markdown code block.

      ### Error Handling:

      - In case of errors or exceptions during code execution, display the error message to the user. This will help in troubleshooting and improving the code.

      ### Request/Response Example 1:

      - The following is a simple example to illustrate how you might respond to a user's request to create a plot.
      - Remember to check if the image file or URL really exists before returning the response. 
      - Remember to add `/data/` before the file name to display the image.

      User Request:

        "Please create a simple line plot of the numbers 1 through 10."

      Your Response:

        ---

        Code:

        ```python
        import matplotlib.pyplot as plt
        x = range(1, 11)
        y = [i for i in x]
        plt.plot(x, y)
        plt.savefig('IMAGE_FILE_NAME')
        ```
        ---

        Output:

        <div class="generated_image">
          <img src="/data/IMAGE_FILE_NAME" />
        </div>

        ---

      ### Request/Response Example 2:

      - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show the output text. Display the output text below the code in a Markdown code block.
      - Remember to check if the image file or URL really exists before returning the response. 

      User Request:

        "Please analyze the sentence 'She saw the boy with binoculars' and show the part-of-speech data."

      Your Response:

        Code:

        ```python
        import spacy

        # Load the English language model
        nlp = spacy.load("en_core_web_sm")

        # Text to analyze
        text = "She saw the boy with binoculars."

        # Perform tokenization and part-of-speech tagging
        doc = nlp(text)

        # Display the tokens and their part-of-speech tags
        for token in doc:
            print(token.text, token.pos_)
        ```

        Output:

        ```markdown
        She PRON
        saw VERB
        the DET
        boy NOUN
        with ADP
        binoculars NOUN
        . PUNCT
        ```

      ### Request/Response Example 3:

      - The following is a simple example to illustrate how you might respond to a user's request to run a Python code and show a link.
      - Remember to check if the image file or URL really exists before returning the response. 

      User Request:

        "Please create a Plotly scatter plot of the numbers 1 through 10."

      Your Response:

        Code:

        ```python
          import plotly.graph_objects as go

          x = list(range(1, 11))
          y = x

          fig = go.Figure(data=go.Scatter(x=x, y=y, mode='markers'))
          fig.write_html('FILE_NAME')
        ```

        Output:

        <div><a href="/data/FILE_NAME" target="_blank">Result</a></div>

      ### Request/Response Example 4:

      - The following is a simple example to illustrate how you might respond to a user's request to show an audio/video clip.
      - Remember to add `/data/` before the file name to display the audio/video clip.

      Audio Clip:

        <audio controls src="/data/FILE_NAME"></audio>

      Video Clip:

        <video controls src="/data/FILE_NAME"></video>

      [IMPORTANT]: Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag.
    TEXT

    text.strip
  end

  def settings
    {
      "disabled": !CONFIG["ANTHROPIC_API_KEY"],
      "temperature": 0.0,
      "presence_penalty": 0.2,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "image_generation": true,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": true,
      "app_name": "▷ Anthropic Claude (Code Interpreter)",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "image": true,
      "toggle": true,
      "models": [
        "claude-3-5-sonnet-20240620",
        "claude-3-opus-20240229"
      ],
      "tools": [
        {
          "name": "run_code",
          "description": "Run program code and return the output.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "description": "Program that execute the code (e.g., 'python')"
              },
              "code": {
                "type": "string",
                "description": "Program code to be executed."
              },
              "extension": {
                "type": "string",
                "description": "File extension of the code when it is temporarily saved to be run (e.g., 'py')"
              }
            },
            "required": ["command", "code", "extension"]
          }
        },
        {
          "name": "run_bash_command",
          "description": "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "description": "Bash command to be executed."
              }
            },
            "required": ["command"]
          }
        },
        {
          "name": "lib_installer",
          "description": "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "description": "Library name to be installed."
              },
              "packager": {
                "type": "string",
                "enum": ["pip", "apt"],
                "description": "Package manager to be used for installation."
              }
            },
            "required": ["command", "packager"]
          }
        },
        {
          "name": "run_jupyter",
          "description": "Start a Jupyter Lab server.",
          "input_schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string",
                "enum": ["run", "stop"],
                "description": "Command to start or stop the Jupyter Lab server."
              }
            },
            "required": ["command"]
          }
        },
        {
          "name": "fetch_text_from_file",
          "description": "Fetch the text from a file and return its content.",
          "input_schema": {
            "type": "object",
            "properties": {
              "file": {
                "type": "string",
                "description": "File name or file path"
              }
            },
            "required": ["file"]
          }
        },
        {
          "name": "fetch_web_content",
          "description": "Fetch the content of the web page of the given URL and return it.",
          "input_schema": {
            "type": "object",
            "properties": {
              "url": {
                "type": "string",
                "description": "URL of the web page."
              }
            },
            "required": ["url"]
          }
        }
      ]
    }
  end

  attr_accessor :thinking
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
      result = result.gsub(/#{old}\n?/m){ new }
    end

    result
  end

  def get_thinking_text(result)
    @thinking += result.scan(/<thinking>.*?<\/thinking>/m) if result
  end

  def process_json_data(app, session, body, call_depth, &block)

    obj = session[:parameters]

    buffer = ""
    texts = []
    tool_calls = []
    finish_reason = nil
    content_type = "text"

    if body.respond_to?(:each)
      body.each do |chunk|
        break if /\Rdata: [DONE]\R/ =~ chunk

        buffer << chunk
        scanner = StringScanner.new(buffer)
        pattern = /data: (\{.*?\})(?=\n|\z)/

        until scanner.eos?
          matched = scanner.scan_until(pattern)
          if matched
            json_data = matched.match(pattern)[1]
            begin
              json = JSON.parse(json_data)

              new_content_type = json.dig('content_block', 'type')
              if new_content_type == "tool_use"
                json["content_block"]["input"] = ""
                tool_calls << json["content_block"]
              end
              content_type = new_content_type if new_content_type

              if content_type == "tool_use"
                if json.dig('delta', 'partial_json')
                  fragment = json.dig('delta', 'partial_json').to_s
                  next if !fragment || fragment == ""
                  tool_calls.last["input"] << fragment
                end

                if json.dig('delta', 'stop_reason')
                  stop_reason = json.dig('delta', 'stop_reason')
                  case stop_reason
                  when "tool_use"
                    finish_reason = "tool_use"
                    res1 = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
                    block&.call res1
                  end
                end
              else
                if json.dig('delta', 'text')
                  fragment = json.dig('delta', 'text').to_s
                  next if !fragment || fragment == ""
                  texts << fragment

                  # fragment.split(//).each do |char|
                  #   res = { "type" => "fragment", "content" => char }
                  #   block&.call res
                  #   sleep 0.01
                  # end

                  res = {
                    "type" => "fragment",
                    "content" => fragment
                  }
                  block&.call res
                end

                if json.dig('delta', 'stop_reason')
                  stop_reason = json.dig('delta', 'stop_reason')
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
    end

    result = if texts.empty?
               nil
             else
               texts.join("")
             end


    if tool_calls.any?
      get_thinking_text(result)

      call_depth += 1

      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      context = []
      context << {
        "role" => "assistant",
        "content" => []
      }

      context.last["content"] << {
        "type" => "text",
        "text" => result
      } if result

      tool_calls.each do |tool_call|
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
      end

      process_functions(app, session, tool_calls, context, call_depth, &block)

    elsif result

      case session[:parameters]["model"]
      when /opus/
        result = add_replacements(result)
        result = add_replacements(@thinking.join("\n")) + result
        result = result.gsub(/<thinking>.*?<\/thinking>/m, "")
      when /sonnet/
        if !@leftover.empty?
          leftover_assistant = @leftover.filter { |x| x["role"] == "assistant" }
          result = leftover_assistant.map { |x| x.dig("content", 0, "text") }.join("\n") + result
        end
      end
      @leftover.clear

      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason}
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => {"content" => result}
            }
          ]
        }
      ]
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["ANTHROPIC_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: ANTHROPIC_API_KEY not found.  Please set the ANTHROPIC_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    # Get the parameters from the session
    obj = session[:parameters]
    app = obj["app_name"]

    # Get the parameters from the session
    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))

    temperature = obj["temperature"] ? obj["temperature"].to_f : nil
    max_tokens = obj["max_tokens"] ? obj["max_tokens"].to_i : nil
    top_p = obj["top_p"] ? obj["top_p"].to_f : nil

    tools = settings[:tools] ? settings[:tools] : []

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    message = obj["message"].to_s

    # If the app is monadic, the message is passed through the monadic_map function
    if obj["monadic"].to_s == "true" && message != ""
      message = monadic_unit(message) if message != ""
      html = markdown_to_html(obj["message"]) if message != ""
    elsif message != ""
      html = markdown_to_html(message)
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
                "active" => true,
              }
      }
      res["image"] = obj["image"] if obj["image"]
      block&.call res
      session[:messages] << res["content"]
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    begin
      session[:messages].each { |msg| msg["active"] = false }
      context = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    rescue
      context = []
    end

    # Set the headers for the API request
    headers = {
      "anthropic-version" => "2023-06-01",
      "content-type" => "application/json",
      "x-api-key" => api_key
    }

    # Set the body for the API request
    body = {
      "system" => initial_prompt,
      "model" => obj["model"],
      "stream" => true,
      "tool_choice" => {"type": "auto"}
    }

    body["temperature"] = temperature if temperature
    body["max_tokens"] = max_tokens if max_tokens
    body["top_p"] = top_p if top_p

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = APPS[app].settings[:tools]
    else
      body.delete("tools")
      body.delete("tool_choice")
    end

    # The context is added to the body

    messages = context.compact.map do |msg|
      message = { "role" => msg["role"], "content" => [ {"type" => "text", "text" => msg["text"]} ] }
      if msg["image"] && role == "user"
        message["content"] << {
          "type" => "image",
          "source" => {
            "type" => "base64",
            "media_type" => msg["image"]["type"],
            "data" => msg["image"]["data"].split(",")[1]
          }
        }
      end
      message
    end

    # Remove assistant messages until the first user message
    messages.shift while messages.first["role"] != "user"

    # if there is no user message, add a placeholder
    if messages.empty?
      messages << {
        "role" => "user",
        "content" => [
          {
            "type" => "text",
            "text" => "OK"
          }
        ]
      }
    end

    body["messages"] = messages

    if role == "tool"
      body["messages"] += obj["function_returns"]
      @leftover += obj["function_returns"]
    end

    # Call the API
    target_uri = "#{API_ENDPOINT}/messages"
    headers["Accept"] = "text/event-stream"
    http = HTTP.headers(headers)

    success = false
    MAX_RETRIES.times do
      res = http.timeout(connect: OPEN_TIMEOUT,
                         write: WRITE_TIMEOUT,
                         read: READ_TIMEOUT).post(target_uri, json: body)
      if res.status.success?
        success = true
        break
      end
      sleep RETRY_DELAY
    end

    unless res.status.success?
      error_report = JSON.parse(res.body)["error"]
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report["message"]}" }
      block&.call res
      return [res]
    end

    return process_json_data(app, session, res.body, call_depth, &block)

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

  def process_functions(app, session, tools, context, call_depth, &block)
    content = []
    obj = session[:parameters]
    tools.each do |tool_call|
      tool_name = tool_call["name"]

      begin
        argument_hash = tool_call["input"]
      rescue
        argument_hash = {}
      end

      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      tool_return = APPS[app].send(tool_name.to_sym, **argument_hash) 

      if !tool_return
        return [{ "type" => "error", "content" => "ERROR: Tool '#{tool_name}' failed" }]
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

    # return Array
    api_request("tool", session, call_depth: call_depth, &block)
  end
end
