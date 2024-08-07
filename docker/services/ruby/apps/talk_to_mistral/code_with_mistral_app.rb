class CodeWithMistral < MonadicApp
  include UtilitiesHelper

  MAX_FUNC_CALLS = 10
  API_ENDPOINT = "https://api.mistral.ai/v1"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1

  def icon
    "<i class='fa-solid fa-m'></i>"
  end

  def description
    "This is an application that allows you to run Python code with Mistral AI"
  end

  attr_reader :models

  def initialize
    @models = list_models
    super
  end

  def list_models
    return @models if @models && !@models.empty?

    api_key = CONFIG["MISTRAL_API_KEY"]
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
        model_data = JSON.parse(res.body)
        model_data["data"].sort_by do |model|
          model["created"]
        end.reverse.map do |model|
          model["id"]
        end.filter do |model|
          !model.include?("embed")
        end
      end
    rescue HTTP::Error, HTTP::TimeoutError
      []
    end
  end

  def initial_prompt
    text = <<~TEXT
      You are an assistant designed to help users write and run code and visualize data upon their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze. A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment.

      The user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch plain text from a text file (e.g., markdown, text, program scripts, etc.), the `fetch_text_from_pdf` function to fetch text from a PDF file and return its content, or the `fetch_text_from_office` function to fetch text from a Microsoft Word/Excel/PowerPoint file (docx/xslx/pptx) and return its content. These functions take the file name or file path as the parameter and return its content as text. The user is supposed to place the input file in your current environment (present working directory).

      If the user's request is too complex, please suggest that the user break it down into smaller parts and suggest possible next steps.

      If you need to run a Python code, follow the instructions below:

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the `command` name such as `python` or `ruby`, your program `code` to be executed with the command, and the file `extension` with which the code is stored in a temporary local file. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

      If you need to check the availability of a certain file or command in the bash, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

      If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it.

      If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

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

      [IMPORTANT]: Remember that you must show images and other data files you generate in your current directory using `/data/FILE_NAME` with the `/data` prefix in the `src` attribute of the HTML tag. It is the case with markdown image links: Use the format `![alt text](/data/FILE_NAME)`.
    TEXT

    text.strip
  end

  def prompt_suffix
    "Use the same language as the user and insert an ascii emoji that you deem appropriate for the user's input at the beginning of your response. When you use emoji, it should be something like 😀 instead of `:smiley:`. Avoid repeating words or phrases in your responses."
  end

  def settings
    {
      "disabled": !CONFIG["MISTRAL_API_KEY"],
      "temperature": 0.0,  # Adjusted temperature
      "top_p": 1.0,        # Adjusted top_p
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "prompt_suffix": prompt_suffix,
      "image_generation": false,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "mathjax": false,
      "app_name": "▷ Mistral AI (Code Interpreter)",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "image": false,
      "toggle": false,
      "models": ["mistral-large-latest"],
      "tools": [
        {
          "type": "function",
          "function": {
            "name": "run_code",
            "description": "Run program code and return the output.",
            "parameters": {
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
          }
        },
        {
          "type": "function",
          "function": {
            "name": "lib_installer",
            "description": "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: `pip install`, `apt-get install -y`.",
            "parameters": {
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
          }
        },
        {
          "type": "function",
          "function": {
            "name": "run_bash_command",
            "description": "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
            "parameters": {
              "type": "object",
              "properties": {
                "command": {
                  "type": "string",
                  "description": "Bash command to be executed."
                }
              },
              "required": ["command"]
            }
          }
        },
        {
          "type": "function",
          "function": {
            "name": "fetch_web_content",
            "description": "Fetch the content of the web page of the given URL and return it.",
            "parameters": {
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
        },
        {
          "type": "function",
          "function": {
            "name": "fetch_text_from_file",
            "description": "Fetch the text from a file and return its content.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path"
                }
              },
              "required": ["file"]
            }
          }
        },
        {
          "type": "function",
          "function": {
            "name": "fetch_text_from_office",
            "description": "Fetch the text from the Microsoft Word/Excel/PowerPoint file and return it.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path of the Microsoft Word/Excel/PowerPoint file."
                }
              },
              "required": ["file"]
            }
          }
        },
        {
          "type": "function",
          "function": {
            "name": "fetch_text_from_pdf",
            "description": "Fetch the text from the PDF file and return it.",
            "parameters": {
              "type": "object",
              "properties": {
                "pdf": {
                  "type": "string",
                  "description": "File name or file path of the PDF"
                }
              },
              "required": ["pdf"]
            }
          }
        }
      ]
    }
  end

  def process_json_data(app, session, body, call_depth, &block)
    buffer = ""
    texts = {}
    tools = {}
    finish_reason = nil

    body.each do |chunk|
      begin
        if buffer.valid_encoding? == false
          buffer << chunk
          next
        end

        buffer << chunk

        data_items = buffer.scan(/data: \{.*\}/)
        next if data_items.nil? || data_items.empty?

        data_items.each do |item|
          data_content = item.match(/data: (\{.*\})/)
          next if data_content.nil? || !data_content[1]

          json = JSON.parse(data_content[1])

          finish_reason = json.dig("choices", 0, "finish_reason")
          case finish_reason
          when "length"
            finish_reason = "length"
          when "stop"
            finish_reason = "stop"
          else
            finish_reason = nil
          end

          if json.dig("choices", 0, "delta", "content")
            id = json["id"]
            texts[id] ||= json
            choice = texts[id]["choices"][0]
            choice["message"] ||= choice["delta"].dup
            choice["message"]["content"] ||= ""

            fragment = json.dig("choices", 0, "delta", "content").to_s
            choice["message"]["content"] << fragment

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

            id = json["id"]
            tools[id] ||= json
            choice = tools[id]["choices"][0]
            choice["message"] ||= choice["delta"].dup

            if choice["finish_reason"] == "function_call"
              break
            end
          end
        rescue JSON::ParserError => e
          pp e.message
          pp e.backtrace
          pp e.inspect
        end
        buffer = ""
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.empty? ? nil : texts.first[1]

    if tools.any?
      tools = tools.first[1].dig("choices", 0, "message", "tool_calls")
      context = []
      res = { "role" => "assistant" }
      res["tool_calls"] = tools.map do |tool|
        {
          "id" => tool["id"],
          "function" => tool["function"]
        }
      end
      context << res

      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tools, context, call_depth, &block)

      if new_results
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
        escaped = function_call["arguments"]
        argument_hash = JSON.parse(escaped)
      rescue JSON::ParserError
        argument_hash = {}
      end

      converted = {}
      argument_hash.each_with_object(converted) do |(k, v), memo|
        # skip if the value is nil or null but not if it is of the string class
        next if /null/ =~ v.to_s.strip || (v.class != String && v.to_s.strip.empty?)

        memo[k.to_sym] = v
        memo
      end

      begin
        function_return = APPS[app].send(function_name.to_sym, **converted)
      rescue StandardError => e
        function_return = "ERROR: #{e.message}"
      end

      context << {
        role: "tool",
        tool_call_id: tool_call["id"],
        name: function_name,
        content: function_return.to_s
      }
    end

    obj["function_returns"] = context

    sleep RETRY_DELAY
    api_request("tool", session, call_depth: call_depth, &block)
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    session[:messages].delete_if do |msg|
      msg["role"] == "assistant" && msg["content"].to_s == ""
    end

    begin
      api_key = CONFIG["MISTRAL_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: MISTRAL_API_KEY not found. Please set the MISTRAL_API_KEY environment variable in the ~/monadic/data/.env file."
      res = { "type" => "error", "content" => error_message }
      block&.call res
      return []
    end

    obj = session[:parameters]
    app = obj["app_name"]

    initial_prompt = obj["initial_prompt"].gsub("{{DATE}}", Time.now.strftime("%Y-%m-%d"))
    max_tokens = obj["max_tokens"]&.to_i
    temperature = obj["temperature"].to_f
    top_p = obj["top_p"].to_f
    top_p = 0.01 if top_p == 0.0
    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

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
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                } }
        block&.call res
      end

      if message != "" && role == "user"
        res = { "mid" => request_id,
                "role" => role,
                "text" => message,
                "html" => markdown_to_html(message),
                "lang" => detect_language(message),
                "active" => true }
        session[:messages] << res
      end
    end

    if initial_prompt != ""
      initial = { "role" => "system",
                  "text" => initial_prompt,
                  "html" => initial_prompt,
                  "lang" => detect_language(initial_prompt) }
    end

    session[:messages].each { |msg| msg["active"] = false }
    latest_messages = session[:messages].last(context_size).each { |msg| msg["active"] = true }
    context = [initial] + latest_messages

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "model" => obj["model"],
      "temperature" => temperature,
      "top_p" => top_p,
      "safe_prompt" => false,
      "stream" => true,
      "tool_choice" => "auto"
    }

    if obj["tools"] && !obj["tools"].empty?
      body["tools"] = settings[:tools] || []
    end

    body["max_tokens"] = max_tokens if max_tokens

    messages_containing_img = false
    body["messages"] = context.compact.map do |msg|
      { "role" => msg["role"], "content" => msg["text"] }
      message
    end

    if role == "tool"
      body["messages"] += obj["function_returns"]
    elsif role == "user"
      if body["messages"].last["content"]
        body["messages"].last["content"] += "\n\n" + settings[:prompt_suffix] if settings[:prompt_suffix]
      end
    end

    if messages_containing_img
      body["model"] = "gpt-4o-mini"
      body.delete("stop")
    end

    target_uri = "#{API_ENDPOINT}/chat/completions"
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
      error_report = JSON.parse(res.body)
      pp error_report
      res = { "type" => "error", "content" => "API ERROR: #{error_report}" }
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
end
