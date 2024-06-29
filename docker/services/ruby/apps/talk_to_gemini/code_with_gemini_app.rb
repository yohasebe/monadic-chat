class CodeWithGemini < MonadicApp
  include UtilitiesHelper

  API_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta"
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60
  MAX_RETRIES = 5
  RETRY_DELAY = 1
  MAX_FUNC_CALLS = 5

  def icon
    "<i class='fab fa-google'></i>"
  end

  def description
    "This is an application that allows you to run Python code with Google Gemini"
  end

  def initial_prompt
    text = <<~TEXT
      You are an assistant designed to help users write and run code and visualize data upon their requests. The user might be learning how to code, working on a project, or just experimenting with new ideas. You support the user every step of the way. Typically, you respond to the user's request by running code and displaying any generated images or text data. Below are detailed instructions on how you do this.

      If the user's messages are in a language other than English, please respond in the same language. If automatic language detection is not possible, kindly ask the user to specify their language at the beginning of their request.

      If the user refers to a specific web URL, please fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns its contents. Throughout the conversation, the user can provide a new URL to analyze.

      A copy of the text file saved by `fetch_web_content` is stored in the current directory of the code running environment. Use the `fetch_text_from_file` function to fetch the text from the file and return its content. Give the base file name as the parameter to the function.

      If the user's request is too complex, please suggest that the user break it down into smaller parts and suggest possible next steps.

      If you need to run a Python code, follow the instructions below:

      ### Basic Procedure:

      To execute the code, use the `run_code` function with the `command` name such as `python` or `ruby`, your program `code` to be executed with the command, and the file `extension` with which the code is stored in a temporary local file. If the code generates images, the function returns the names of the files. Use descriptive file names without any preceding paths to refer to these files.

      If you need to check the availability of a certain file or command in the bash, use the `run_bash_command` function. You are allowed to access the Internet to download the required files or libraries.

      If the command or library is not available in the environment, you can use the `lib_installer` function to install the library using the package manager. The package manager can be pip or apt. Check the availability of the library before installing it.

      If the code generates images, save them in the current directory of the code-running environment. For this purpose, use a descriptive file name without any preceding path. When multiple image file types are available, SVG is preferred.

      If the user asks for it, you can also start a Jupyter Lab server using the `run_jupyter(command)` function. If successful, you should provide the user with the URL to access the Jupyter Lab server in a way that the user can easily click on it and the new tab opens in the browser using `<a href="URL" target="_blank">Jupyter Lab</a>`.
      
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
      "app_name": "Google Gemini (Code Interpreter)",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "toggle": true,
      "models": [
        "gemini-1.5-pro-latest",
        "gemini-1.5-pro",
      ],
      "tools": {
        "function_declarations": [
          {
            name: "fetch_web_content",
            description: "Fetch the content of the web page of the given URL and return it.",
            parameters: {
              type: "object",
              properties: {
                url: {
                  description: "URL of the web page.",
                  type: "string"
                }
              },
              required: ["url"]
            }
          },
          {
            name: "fetch_text_from_file",
            description: "Fetch the text from a file and return its content.",
            parameters: {
              type: "object",
              properties: {
                file: {
                  type: "string",
                  description: "File name or file path"
                }
              },
              required: ["file"]
            }
          },
          {
            name: "run_jupyter",
            description: "Start a Jupyter Lab server.",
            parameters: {
              type: "object",
              properties: {
                "command": {
                  type: "string",
                  description: "Command to start or stop the Jupyter Lab server. It must be either 'run' or 'stop'."
                }
              },
              required: ["command"]
            }
          },
          {
            name: "run_code",
            description: "Run program code and return the output.",
            parameters: {
              type: "object",
              properties: {
                command: {
                  type: "string",
                  description: "Code execution command (e.g., 'python')"
                },
                code: {
                  type: "string",
                  description: "Code to be executed."
                },
                extension: {
                  type: "string",
                  description: "File extension of the code (e.g., 'py')"
                }
              },
              required: ["command", "code", "extension"]
            }
          },
          {
            name: "run_bash_command",
            description: "Run a bash command and return the output. The argument to `command` is provided as part of `docker exec -w shared_volume container COMMAND`.",
            parameters: {
              type: "object",
              properties: {
                command: {
                  type: "string",
                  description: "Bash command to be executed."
                }
              },
              required: ["command"]
            }
          },
          {
            name: "lib_installer",
            description: "Install a library using the package manager. The package manager can be pip or apt. The command is the name of the library to be installed. The `packager` parameter corresponds to the folllowing commands respectively: ``pip install`, `apt-get install -y`.",
            parameters: {
              type: "object",
              properties: {
                command: {
                  type: "string",
                  description: "Library name to be installed."
                },
                packager: {
                  type: "string",
                  description: "Package manager to be used for installation. It must be either 'pip' or 'apt'."
                }
              },
              required: ["command", "packager"]
            }
          },
        ]
      }
    }
  end
  def process_json_data(app, session, body, call_depth, &block)
    obj = session[:parameters]
    buffer = ""
    texts = []
    tool_calls = []
    finish_reason = nil

    in_text_generation = false

    body.each do |chunk|
      buffer << chunk
      if /(\{\s*\"candidates\":.*\})/m =~ buffer.strip
        json = $1
        begin
          candidates = JSON.parse(json).dig("candidates")
          candidate = candidates.first

          finish_reason = candidate["finishReason"]
          case finish_reason
          when "MAX_TOKENS"
            finish_reason = "length"
          when "STOP"
            finish_reason = "stop"
          when "SAFETY"
            finish_reason = "safety"
          end

          content = candidate.dig("content")
          next if content.nil?

          content.dig("parts")&.each do |part|
            if part["text"]
              texts << part["text"]
              part["text"].split(//).each do |char|
                res = { "type" => "fragment", "content" => char }
                block&.call res
                sleep 0.01
              end
            elsif part["functionCall"]
              tool_calls << part["functionCall"]
              res = { "type" => "wait", "content" => "<i class='fas fa-cogs'></i> CALLING FUNCTIONS" }
              block&.call res
            end
          end
          buffer = ""
        rescue JSON::ParserError
          # if the JSON parsing fails, the next chunk should be appended to the buffer
          # and the loop should continue to the next iteration
        end
      end
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
    end

    result = texts.empty? ? nil : texts

    if tool_calls.any?
      call_depth += 1
      if call_depth > MAX_FUNC_CALLS
        return [{ "type" => "error", "content" => "ERROR: Call depth exceeded" }]
      end

      new_results = process_functions(app, session, tool_calls, call_depth, &block)

      if result && new_results
        result = result.join("") + "\n" + new_results.dig(0, "choices", 0, "message", "content")
        {"choices" => [{"message" => {"content" => result}}]}
      elsif new_results
        new_results
      elsif result
        {"choices" => [{"message" => {"content" => result.join("")}}]}
      end
    elsif result
      res = { "type" => "message", "content" => "DONE", "finish_reason" => finish_reason}
      block&.call res
      [
        {
          "choices" => [
            {
              "finish_reason" => finish_reason,
              "message" => {"content" => result.join("")}
            }
          ]
        }
      ]
    end
  end

  def process_functions(app, session, tool_calls, call_depth, &block)
    obj = session[:parameters]
    tool_results = {"model_parts" => [], "function_parts" => []}
    tool_calls.each do |tool_call|
      function_name = tool_call["name"]

      begin
        argument_hash = tool_call["args"]
      rescue
        argument_hash = {}
      end
      argument_hash = argument_hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end

      function_return = send(function_name.to_sym, **argument_hash)

      tool_results["model_parts"] << {
        "functionCall" => {
          "name" => function_name,
          "args" => argument_hash
        }
      }
      tool_results["function_parts"] << {
        "functionResponse" => {
          "name" => function_name,
          "response" => {
            "name" => function_name,
            "content" => {
              "result" => function_return.to_s
            }
          }
        }
      }
    end

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
      "system"
    else
      role.downcase
    end
  end

  def api_request(role, session, call_depth: 0, &block)
    num_retrial = 0

    begin
      api_key = CONFIG["GEMINI_API_KEY"]
      raise if api_key.nil?
    rescue StandardError
      pp error_message = "ERROR: GEMINI_API_KEY not found.  Please set the GEMINI_API_KEY environment variable in the ~/monadic/data/.env file."
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

    context_size = obj["context_size"].to_i
    request_id = SecureRandom.hex(4)

    if role != "tool"
      message = obj["message"].to_s

      if obj["monadic"].to_s == "true" && message != ""
        message = monadic_unit(message) if message != ""
        html = markdown_to_html(obj["message"]) if message != ""
      elsif message != ""
        html = markdown_to_html(message)
      end

      if message != "" && role == "user"
        res = { "type" => "user",
                "content" => {
                  "mid" => request_id,
                  "text" => obj["message"],
                  "html" => html,
                  "lang" => detect_language(obj["message"])
                }
        }
        res["image"] = obj["image"] if obj["image"]
        block&.call res
      end

      # If the role is "user", the message is added to the session
      if message != "" && role == "user"
        res = { "mid" => request_id,
                "role" => role,
                "text" => message,
                "html" => markdown_to_html(message),
                "lang" => detect_language(message),
                "active" => true,
        }
        if obj["image"]
          res["image"] = obj["image"]
        end
        session[:messages] << res
      end
    end

    # Old messages in the session are set to inactive
    # and set active messages are added to the context
    if session[:messages].empty?
      session[:messages] << { "role" => "user", "text" => "Hi, there!"}
    end
    session[:messages].each { |msg| msg["active"] = false }
    context = session[:messages].last(context_size).each { |msg| msg["active"] = true }

    # Set the headers for the API request
    headers = {
      "content-type" => "application/json"
    }

    body = {
      safety_settings: [
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
    }

    if temperature || max_tokens || top_p
      body["generationConfig"] = {}
      body["generationConfig"]["temperature"] = temperature if temperature
      body["generationConfig"]["maxOutputTokens"] = max_tokens if max_tokens
      body["generationConfig"]["topP"] = top_p if top_p
    end

    messages_containing_img = false
    body["contents"] = context.compact.map do |msg|
      message = {
        "role" => translate_role(msg["role"]),
        "parts" => [
          { "text" => msg["text"] }
        ]
      }

      if msg["image"] && role == "user"
        message["parts"] << {
          "inlineData" => {
            "mimeType" => msg["image"]["type"],
            "data" => msg["image"]["data"].split(",")[1]
          }
        }
        messages_containing_img = true
      end
      message
    end

    if settings[:tools]
      body["tools"] = settings[:tools]
    end

    if role == "tool"
      body["contents"] << {
        "role" => "model",
        "parts" => obj["tool_results"]["model_parts"]
      }
      body["contents"] << {
        "role" => "function",
        "parts" => obj["tool_results"]["function_parts"]
      }
    end

    target_uri = "#{API_ENDPOINT}/models/#{obj['model']}:streamGenerateContent?key=#{api_key}"

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
end
