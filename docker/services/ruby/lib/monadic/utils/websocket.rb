# frozen_string_literal: true

require 'timeout'

module WebSocketHelper
  # Handle websocket connection
  
  # Initialize token counting in a background thread
  def initialize_token_counting(text, encoding_name="o200k_base")
    # Return immediately if no text
    return nil if text.nil? || text.empty?
    
    # Use Thread.new with lower priority to avoid impacting TTS
    Thread.new do
      result = nil
      begin
        # Add a small delay to prioritize TTS thread startup if running concurrently
        sleep 0.05 if Thread.list.any? { |t| t[:type] == :tts }
        
        # Set thread type for identification
        Thread.current[:type] = :token_counter
        
        # Do the actual token counting
        result = MonadicApp::TOKENIZER.count_tokens(text, encoding_name)
      rescue => e
        # Silently handle token counting errors
      end
      
      # Thread's return value
      result
    end
  end

  # check if the total tokens of past messages is less than max_tokens in obj
  # token count is calculated using tiktoken_ruby gem
  def check_past_messages(obj)
    # filter out any messages of type "search"
    messages = session[:messages].filter { |m| m["type"] != "search" }

    res = false
    max_input_tokens = obj["max_input_tokens"].to_i
    context_size = obj["context_size"].to_i
    tokenizer_available = true

    # gpt-4o => o200k_base;
    # model_name = /gpt-4o/ =~ obj["model"] ? "gpt-4o" : "gpt-3.5-turbo"
    # encoding_name = MonadicApp::TOKENIZER.get_encoding_name(model_name)
    encoding_name = "o200k_base"

    begin
      # Calculate token count for each message and mark as active if not already calculated
      messages.each do |m|
        m["tokens"] ||= begin
          # If this is the most recent message and we have precounted tokens, use them
          if m == messages.last && defined?(Thread.current[:token_count_result]) && Thread.current[:token_count_result]
            Thread.current[:token_count_result]
          else
            # Otherwise count tokens normally
            MonadicApp::TOKENIZER.count_tokens(m["text"], encoding_name)
          end
        end
        m["active"] = true
      end

      # Filter active messages and calculate total token count
      active_messages = messages.select { |m| m["active"] }.reverse
      total_tokens = active_messages.sum { |m| m["tokens"] || 0 }

      # Remove oldest messages until total token count and message count are within limits
      until active_messages.empty? || total_tokens <= max_input_tokens
        last_message = active_messages.pop
        last_message["active"] = false
        total_tokens -= last_message["tokens"] || 0
        res = true
        break if context_size.positive? && active_messages.size <= context_size
      end

      # Calculate total token counts for different roles
      count_total_system_tokens = messages.filter { |m| m["role"] == "system" }.sum { |m| m["tokens"] || 0 }
      count_total_input_tokens = messages.filter { |m| m["role"] == "user" }.sum { |m| m["tokens"] || 0 }
      count_total_output_tokens = messages.filter { |m| m["role"] == "assistant" }.sum { |m| m["tokens"] || 0 }
      count_active_tokens = active_messages.sum { |m| m["tokens"] || 0 }
      count_all_tokens = messages.sum { |m| m["tokens"] || 0 }
    rescue StandardError => e
      pp e.message
      pp e.backtrace
      pp e.inspect
      tokenizer_available = false
    end

    # Return information about the state of the messages array
    res = { changed: res,
            count_total_system_tokens: count_total_system_tokens,
            count_total_input_tokens: count_total_input_tokens,
            count_total_output_tokens: count_total_output_tokens,
            count_total_active_tokens: count_active_tokens,
            count_all_tokens: count_all_tokens,
            count_messages: messages.size,
            count_active_messages: active_messages.size,
            encoding_name: encoding_name }
    res[:error] = "Error: Token count not available" unless tokenizer_available
    res
  end

  # List available ElevenLabs voices
  # @param api_key [String, nil] Optional API key
  # @return [Array] Array of voice data
  def list_elevenlabs_voices(api_key = nil)
    # Use provided API key or default from config
    api_key ||= CONFIG["ELEVENLABS_API_KEY"] if defined?(CONFIG)
    return [] unless api_key
    
    # Direct implementation to avoid dependency issues with InteractionUtils
    begin
      url = URI("https://api.elevenlabs.io/v1/voices")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request["xi-api-key"] = api_key
      response = http.request(request)
      
      return [] unless response.is_a?(Net::HTTPSuccess)
      
      voices = response.read_body
      JSON.parse(voices)&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end || []
    rescue StandardError => e
      []
    end
  end

  # Handle the LOAD message by preparing and sending relevant data
  # @param ws [Faye::WebSocket] WebSocket connection
  def handle_load_message(ws)
    # Handle error if present
    if session[:error]
      ws.send({ "type" => "error", "content" => session[:error] }.to_json)
      session[:error] = nil
    end
    
    # Prepare app data
    apps_data = prepare_apps_data
    
    # Filter and prepare messages
    filtered_messages = prepare_filtered_messages
    
    # Send app data
    push_apps_data(ws, apps_data, filtered_messages)
    
    # Handle voice data
    push_voice_data(ws)
    
    # Update message status
    update_message_status(ws, filtered_messages)
  end
  
  # Prepare apps data with settings
  # @return [Hash] Apps data with settings
  def prepare_apps_data
    return {} unless defined?(APPS)
    
    apps = {}
    APPS.each do |k, v|
      apps[k] = {}
      v.settings.each do |p, m|
        # Special case for models array to ensure it's properly sent as JSON
        if p == "models" && m.is_a?(Array)
          apps[k][p] = m.to_json
        else
          apps[k][p] = m ? m.to_s : nil
        end
      end
      v.api_key = settings.api_key if v.respond_to?(:api_key=) && settings.respond_to?(:api_key)
    end
    apps
  end
  
  # Filter and prepare messages for display
  # @return [Array] Filtered and formatted messages
  def prepare_filtered_messages
    # Filter messages only once
    filtered_messages = session[:messages].filter { |m| m["type"] != "search" }
    
    # Convert markdown to HTML for assistant messages if html field is missing
    filtered_messages.each do |m|
      if m["role"] == "assistant" && !m["html"]
        m["html"] = if session["parameters"]&.[]("monadic") && defined?(APPS) && 
                      session["parameters"]["app_name"] && 
                      APPS[session["parameters"]["app_name"]]&.respond_to?(:monadic_html)
                    APPS[session["parameters"]["app_name"]].monadic_html(m["text"])
                  else
                    markdown_to_html(m["text"])
                  end
      end
    end
    
    filtered_messages
  end
  
  # Log error with appropriate level based on environment
  # @param message [String] Error message prefix
  # @param error [StandardError] The error object
  # @param level [Symbol] Log level (:info, :warn, :error, etc)
  def log_error(message, error, level = :error)
    # Skip verbose logging in test environment
    return if defined?(RSpec)
    
    # Use Rails logger if available
    if defined?(Rails) && Rails.logger
      Rails.logger.send(level, "#{message}: #{error.message}")
      Rails.logger.debug(error.backtrace.join("\n")) if level == :error
    # Use Ruby logger if available
    elsif defined?(Logger) && instance_variable_defined?(:@logger)
      @logger.send(level, "#{message}: #{error.message}")
      @logger.debug(error.backtrace.join("\n")) if level == :error
    # Fallback to puts for development
    elsif ENV["RACK_ENV"] != "test"
      puts "#{level.to_s.upcase}: #{message}: #{error.message}"
      puts error.backtrace.join("\n") if level == :error
    end
  end
  
  # Push apps data to WebSocket
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param apps [Hash] Apps data
  # @param filtered_messages [Array] Filtered messages
  def push_apps_data(ws, apps, filtered_messages)
    @channel.push({ "type" => "apps", "content" => apps, "version" => session[:version], "docker" => session[:docker] }.to_json) unless apps.empty?
    @channel.push({ "type" => "parameters", "content" => session[:parameters] }.to_json) unless session[:parameters].empty?
    @channel.push({ "type" => "past_messages", "content" => filtered_messages }.to_json) unless session[:messages].empty?
  end
  
  # Push voice data to WebSocket
  # @param ws [Faye::WebSocket] WebSocket connection
  def push_voice_data(ws)
    elevenlabs_voices = list_elevenlabs_voices
    if elevenlabs_voices && !elevenlabs_voices.empty?
      @channel.push({ "type" => "elevenlabs_voices", "content" => elevenlabs_voices }.to_json)
    end
  end
  
  # Update message status and push info
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param filtered_messages [Array] Filtered messages
  def update_message_status(ws, filtered_messages)
    past_messages_data = check_past_messages(session[:parameters])
    
    # Reuse filtered_messages for change_status
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end
  
  # Handle DELETE message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_delete_message(ws, obj)
    # Delete the message
    session[:messages].delete_if { |m| m["mid"] == obj["mid"] }
    
    # Check message status
    past_messages_data = check_past_messages(session[:parameters])
    
    # Filter messages
    filtered_messages = prepare_filtered_messages
    
    # Update status
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end
  
  # Handle EDIT message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_edit_message(ws, obj)
    # Find the message to edit
    message_to_edit = session[:messages].find { |m| m["mid"] == obj["mid"] }
    
    if message_to_edit
      # Update the message text
      message_to_edit["text"] = obj["content"]
      
      # Generate HTML content if needed
      html_content = generate_html_for_message(message_to_edit, obj["content"])
      
      # Create response with updated HTML for the client
      response = {
        "type" => "edit_success",
        "content" => "Message updated successfully",
        "mid" => obj["mid"],
        "role" => message_to_edit["role"],
        "html" => html_content
      }
      
      # Push the response
      @channel.push(response.to_json)
      
      # Update message status
      update_message_status_after_edit
    else
      # Message not found
      @channel.push({ "type" => "error", "content" => "Message not found for editing" }.to_json)
    end
  end
  
  # Generate HTML content for a message
  # @param message [Hash] The message to generate HTML for
  # @param content [String] The text content
  # @return [String, nil] The HTML content or nil
  def generate_html_for_message(message, content)
    return nil unless message["role"] == "assistant"
    
    html_content = if session["parameters"]&.[]("monadic") && 
                     defined?(APPS) && 
                     session["parameters"]["app_name"] && 
                     APPS[session["parameters"]["app_name"]]&.respond_to?(:monadic_html)
                   APPS[session["parameters"]["app_name"]].monadic_html(content)
                 else
                   markdown_to_html(content)
                 end
    
    message["html"] = html_content
    html_content
  end
  
  # Update message status after edit
  def update_message_status_after_edit
    past_messages_data = check_past_messages(session[:parameters])
    
    # Filter messages only once and store in filtered_messages
    filtered_messages = session[:messages].filter { |m| m["type"] != "search" }
    
    # Update status to reflect any changes
    @channel.push({ "type" => "change_status", "content" => filtered_messages }.to_json) if past_messages_data[:changed]
    @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
  end
  
  # Handle AUDIO message
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_audio_message(ws, obj)
    if obj["content"].nil?
      @channel.push({ "type" => "error", "content" => "Voice input is empty" }.to_json)
      return
    end
    
    # Decode audio content
    blob = Base64.decode64(obj["content"])
    
    # Get configuration
    model = get_stt_model
    format = obj["format"] || "webm"
    
    # Process the transcription
    process_transcription(ws, blob, format, obj["lang_code"], model)
  end
  
  # Get the speech-to-text model from config
  # @return [String] The model name
  def get_stt_model
    defined?(CONFIG) && CONFIG["STT_MODEL"] ? CONFIG["STT_MODEL"] : "gpt-4o-transcribe"
  end
  
  # Process audio transcription
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param blob [String] The decoded audio data
  # @param format [String] The audio format
  # @param lang_code [String] The language code
  # @param model [String] The model to use
  def process_transcription(ws, blob, format, lang_code, model)
    begin
      # Request transcription
      res = stt_api_request(blob, format, lang_code, model)
      
      if res["text"] && res["text"] == ""
        @channel.push({ "type" => "error", "content" => "The text input is empty" }.to_json)
      elsif res["type"] && res["type"] == "error"
        # Include format information in error message for debugging
        error_message = "#{res["content"]} (using format: #{format}, model: #{model})"
        @channel.push({ "type" => "error", "content" => error_message }.to_json)
      else
        send_transcription_result(ws, res, model)
      end
    rescue StandardError => e
      # Log the error but don't crash the application
      log_error("Error processing transcription", e) 
      
      # Send a generic error message to the client
      @channel.push({ 
        "type" => "error", 
        "content" => "An error occurred while processing your audio"
      }.to_json)
    end
  end
  
  # Calculate confidence and send transcription result
  # @param ws [Faye::WebSocket] WebSocket connection
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  def send_transcription_result(ws, res, model)
    begin
      logprob = calculate_logprob(res, model)
      
      @channel.push({
        "type" => "stt",
        "content" => res["text"],
        "logprob" => logprob
      }.to_json)
    rescue StandardError => e
      # Handle errors in logprob calculation
      @channel.push({
        "type" => "stt",
        "content" => res["text"]
      }.to_json)
    end
  end
  
  # Calculate log probability for transcription confidence
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  # @return [Float, nil] The calculated log probability or nil on error
  def calculate_logprob(res, model)
    case model
    when "whisper-1"
      avg_logprobs = res["segments"].map { |s| s["avg_logprob"].to_f }
    else
      avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
    end
    
    # Calculate average and convert to probability
    Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
  rescue StandardError
    nil
  end

  def websocket_handler(env)
    EventMachine.run do
      queue = Queue.new
      thread = nil
      sid = nil
      
      # Create a new channel for each connection if it doesn't exist
      @channel ||= EventMachine::Channel.new

      ws = Faye::WebSocket.new(env, nil, { ping: 15 })
      ws.on :open do
        sid = @channel.subscribe { |obj| ws.send(obj) }
      end

      ws.on :message do |event|
        obj = JSON.parse(event.data)
        msg = obj["message"] || ""

        case msg
        when "TTS"
          provider = obj["provider"]
          if provider == "elevenlabs"
            voice = obj["elevenlabs_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          res_hash = tts_api_request(text,
                                     provider: provider,
                                     voice: voice,
                                     speed: speed,
                                     response_format: response_format)
          @channel.push(res_hash.to_json)
        when "TTS_STREAM"
          thread&.join
          provider = obj["provider"]
          if provider == "elevenlabs"
            voice = obj["elevenlabs_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          # model = obj["model"]
          tts_api_request(text,
                          provider: provider,
                          voice: voice,
                          speed: speed,
                          response_format: response_format) do |fragment|
            @channel.push(fragment.to_json)
          end
        when "CANCEL"
          thread&.kill
          thread = nil
          queue.clear
          @channel.push({ "type" => "cancel" }.to_json)
        when "PDF_TITLES"
          ws.send({
            "type" => "pdf_titles",
            "content" => list_pdf_titles
          }.to_json)
        when "DELETE_PDF"
          title = obj["contents"]
          res = EMBEDDINGS_DB.delete_by_title(title)
          if res
            ws.send({ "type" => "pdf_deleted", "res" => "success", "content" => "#{title} deleted successfully" }.to_json)
          else
            ws.send({ "type" => "pdf_deleted", "res" => "failure", "content" => "Error deleting #{title}" }.to_json)
          end
        when "CHECK_TOKEN"
          if CONFIG["ERROR"].to_s == "true"
            ws.send({ "type" => "error", "content" => "Error reading <code>~/monadic/config/env</code>" }.to_json)
          else
            token = CONFIG["OPENAI_API_KEY"]

            res = nil
            begin
              res = check_api_key(token) if token

              if token && res.is_a?(Hash) && res.key?("type")
                if res["type"] == "error"
                  ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
                else
                  ws.send({ "type" => "token_verified",
                            "token" => token, "content" => res["content"],
                            # "models" => res["models"],
                            "ai_user_initial_prompt" => MonadicApp::AI_USER_INITIAL_PROMPT }.to_json)
                end
              else
                ws.send({ "type" => "token_not_verified", "token" => "", "content" => "" }.to_json)
              end
            rescue StandardError => e
              ws.send({ "type" => "open_ai_api_error", "token" => "", "content" => "" }.to_json)
            end
          end
        when "PING"
          @channel.push({ "type" => "pong" }.to_json)
        when "RESET"
          session[:messages].clear
          session[:parameters].clear
          session[:error] = nil
          session[:obj] = nil
        when "LOAD"
          handle_load_message(ws)
        when "DELETE"
          handle_delete_message(ws, obj)
        when "EDIT"
          handle_edit_message(ws, obj)
        when "AI_USER_QUERY"
          thread&.join

          aiu_buffer = []

          reversed_messages = []

          session[:messages].each do |m|
            r = m.dup
            case m["role"]
            when "assistant"
              r["role"] = "user"
            when "user"
              r["role"] = "assistant"
            when "system"
              next
            end

            if obj["contents"]["params"]["monadic"].to_s == "true"
              begin
                parsed = JSON.parse(r["text"])
                r["text"] = parsed["message"] || parsed["response"]
              rescue JSON::ParserError
                # do nothing
              end
            end
            reversed_messages << r
          end

          # copy obj["contents"]["params"] to parameters_modified
          parameters_modified = obj["contents"]["params"].dup
          parameters_modified.delete("tools")
          message_text = reversed_messages.pop["text"]

          parameters_modified["message"] = message_text

          # code to use the OpenAI mode for AI User
          api_request = APPS["Chat"].method(:api_request)
          parameters_modified["model"] = CONFIG["AI_USER_MODEL"] || "gpt-4o"

          mini_session = {
            parameters: parameters_modified,
            messages: reversed_messages
          }

          mini_session[:parameters]["initial_prompt"] = mini_session[:parameters]["ai_user_initial_prompt"]
          mini_session[:parameters]["monadic"] = false
          mini_session[:parameters]["temperature"] = 0.0
          mini_session[:parameters]["presence_penalty"] = 1.0
          mini_session[:parameters]["frequency_penalty"] = 1.0
          mini_session[:parameters].delete("prompt_suffix")

          responses = api_request.call("user", mini_session) do |fragment|
            if fragment["type"] == "error"
              @channel.push({ "type" => "error", "content" => "E1:#{fragment}" }.to_json)
            elsif fragment["type"] == "fragment"
              text = fragment["content"]
              @channel.push({ "type" => "ai_user", "content" => text }.to_json)
              aiu_buffer << text unless text.empty? || text == "DONE"
            end
          end

          ai_user_response = aiu_buffer.join
          @channel.push({ "type" => "ai_user_finished", "content" => ai_user_response }.to_json)
        when "HTML"
          thread&.join
          until queue.empty?
            last_one = queue.shift
            begin
              content = last_one["choices"][0]

              text = content["text"] || content["message"]["content"]
              thinking = content["thinking"] || content["message"]["thinking"] || content["message"]["reasoning_content"]

              type_continue = "Press <button class='btn btn-secondary btn-sm contBtn'>continue</button> to get more results\n"
              code_truncated = "[CODE BLOCK TRUNCATED]"

              if content["finish_reason"] && content["finish_reason"] == "length"
                if text.scan(/(?:\A|\n)```/m).size.odd?
                  text += "\n```\n\n> #{type_continue}\n#{code_truncated}"
                else
                  text += "\n\n> #{type_continue}"
                end
              end

              if content["finish_reason"] && content["finish_reason"] == "safety"
                @channel.push({ "type" => "error", "content" => "The API stopped responding because of safety reasons" }.to_json)
              end

              html = if session["parameters"]["monadic"]
                       APPS[session["parameters"]["app_name"]].monadic_html(text)
                     else
                       markdown_to_html(text)
                     end

              if session["parameters"]["response_suffix"]
                html += "\n\n" + session["parameters"]["response_suffix"]
              end

              new_data = { "mid" => SecureRandom.hex(4),
                           "role" => "assistant",
                           "text" => text,
                           "html" => html,
                           "lang" => detect_language(text),
                           "active" => true } # detect_language is called only once here

              new_data["thinking"] = thinking if thinking

              @channel.push({
                "type" => "html",
                "content" => new_data
              }.to_json)

              session[:messages] << new_data
              messages = session[:messages].filter { |m| m["type"] != "search" }
              past_messages_data = check_past_messages(session[:parameters])

              @channel.push({ "type" => "change_status", "content" => messages }.to_json) if past_messages_data[:changed]
              @channel.push({ "type" => "info", "content" => past_messages_data }.to_json)
            rescue StandardError => e
              pp queue
              pp e.message
              pp e.backtrace
              @channel.push({ "type" => "error", "content" => "Something went wrong" }.to_json)
            end
          end
        when "SYSTEM_PROMPT"
          text = obj["content"] || ""

          if obj["mathjax"]
            # the blank line at the beginning is important!
            text << <<~SYSPSUFFIX

            You use the MathJax notation to write mathematical expressions. In doing so, you should follow the format requirements: Use double dollar signs `$$` to enclose MathJax/LaTeX expressions that should be displayed as a separate block; Use single dollar signs `$` before and after the expressions that should appear inline with the text. Without these, the expressions will not render correctly. Either type of MathJax expression should be presntend without surrounding backticks.
              SYSPSUFFIX

            if obj["monadic"] || obj["jupyter"]
              # the blank line at the beginning is important!
              text << <<~SYSPSUFFIX

              Make sure to escape properly in the MathJax expressions.

                Good examples of inline MathJax expressions:
                - `$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$`
                - `$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$`
                - `$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$`
                - `$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$`

              Good examples of block MathJax expressions:
                - `$$1 + 2 + 3 + … + k + (k + 1) = \\\\frac{k(k + 1)}{2} + (k + 1)$$`
                - `$$\\\\textbf{a} + \\\\textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
                - `$$\\\\begin{align} 1 + 2 + … + k + (k+1) &= \\\\frac{k(k+1)}{2} + (k+1)\\\\end{align}$$`
                - `$$\\\\sin(\\\\theta) = \\\\frac{\\\\text{opposite}}{\\\\text{hypotenuse}}$$`
              SYSPSUFFIX
            else
              # the blank line at the beginning is important!
              text << <<~SYSPSUFFIX

              Good examples of inline MathJax expressions:
                - `$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$`
                - `$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$`
                - `$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$`
                - `$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$`

              Good examples of block MathJax expressions:
                - `$$1 + 2 + 3 + … + k + (k + 1) = \frac{k(k + 1)}{2} + (k + 1)$$`
                - `$$\textbf{a} + \textbf{b} = (a_1 + b_1, a_2 + b_2)$$`
                - `$$\begin{align} 1 + 2 + … + k + (k+1) &= \frac{k(k+1)}{2} + (k+1)\end{align}$$`
                - `$$\sin(\theta) = \frac{\text{opposite}}{\text{hypotenuse}}$$`

              Remember that the following are not available in MathJax:
                - `\begin{itemize}` and `\end{itemize}`
              SYSPSUFFIX
            end
          end

          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => "system",
                       "text" => text,
                       "active" => true }
          # Initial prompt is added to messages but not shown as the first message
          # @channel.push({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data

        when "SAMPLE"
          text = obj["content"]
          images = obj["images"]
          new_data = { "mid" => SecureRandom.hex(4),
                       "role" => obj["role"],
                       "text" => text,
                       "active" => true }
          new_data["images"] = images if images
          if obj["role"] == "assistant"
            new_data["html"] = markdown_to_html(text)
          else
            new_data["html"] = text
          end

          @channel.push({ "type" => "html", "content" => new_data }.to_json)
          session[:messages] << new_data
        when "AUDIO"
          handle_audio_message(ws, obj)
        else # fragment
          session[:parameters].merge! obj
          
          # Start background token counting for the user message immediately
          message_text = obj["message"].to_s
          if !message_text.empty?
            # Use o200k_base encoding for most LLMs
            token_count_thread = initialize_token_counting(message_text, "o200k_base")
            Thread.current[:token_count_thread] = token_count_thread
          end

          # Extract TTS parameters if auto_speech is enabled
          # Convert string "true" to boolean true for compatibility
          obj["auto_speech"] = true if obj["auto_speech"] == "true"
          
          if obj["auto_speech"]
            provider = obj["tts_provider"]
            if provider == "elevenlabs"
              voice = obj["elevenlabs_tts_voice"] 
            else
              voice = obj["tts_voice"]
            end
            speed = obj["tts_speed"]
            response_format = "mp3"
            model = "tts-1"
          end

          thread = Thread.new do
            # Set thread type for identification
            Thread.current[:type] = :tts
            
            # If we have a token counting thread, wait for it to complete and save result
            if defined?(token_count_thread) && token_count_thread
              begin
                # Don't wait forever, time out after 2 seconds
                Timeout.timeout(2) do
                  token_count_result = token_count_thread.value
                  if token_count_result
                    Thread.current[:token_count_result] = token_count_result 
                  end
                end
              rescue Timeout::Error
                # Silently continue without precounted tokens
              rescue => e
                # Silently handle errors
              end
            end
            
            buffer = []
            cutoff = false

            app_name = obj["app_name"]
            app_obj = APPS[app_name]

            prev_texts_for_tts = []
            responses = app_obj.api_request("user", session) do |fragment|
              if fragment["type"] == "error"
                @channel.push({ "type" => "error", "content" => fragment }.to_json)
                break
              elsif fragment["type"] == "fragment"
                text = fragment["content"]
                buffer << text unless text.empty? || text == "DONE"
                ps = PragmaticSegmenter::Segmenter.new(text: buffer.join)
                segments = ps.segment
                if !cutoff && segments.size > 2
                  # candidate = segments.first
                  candidate = segments[0...-1].join
                  split = candidate.split("---")
                  if split.empty?
                    cutoff = true
                  end

                  # Process sentence fragments for TTS if auto_speech is enabled
                  if obj["auto_speech"] && !cutoff && !obj["monadic"]
                    text = split[0] || ""
                    if text != "" && candidate != ""
                      previous_text = prev_texts_for_tts.empty? ? nil : prev_texts_for_tts[-1]
                      res_hash = tts_api_request(text,
                                                 previous_text: previous_text, 
                                                 provider: provider,
                                                 voice: voice,
                                                 speed: speed,
                                                 response_format: response_format)
                      prev_texts_for_tts << text
                      @channel.push(res_hash.to_json)
                    end
                  end

                  buffer = [segments[-1]]
                end
              end
              @channel.push(fragment.to_json)
              sleep 0.01
            end

            Thread.exit if !responses || responses.empty?

            # We play back TTS at the end of processing, regardless of whether 
            # this is a regular message or initiated from assistant
            # Convert string "true" to boolean true for compatibility
            obj["auto_speech"] = true if obj["auto_speech"] == "true"
            
            if obj["auto_speech"] && !cutoff && !obj["monadic"]
              text = buffer.join
              previous_text = prev_texts_for_tts.empty? ? nil : prev_texts_for_tts[-1]
              res_hash = tts_api_request(text, 
                                        previous_text: previous_text,
                                        provider: provider, 
                                        voice: voice,
                                        speed: speed,
                                        response_format: response_format)
              @channel.push(res_hash.to_json)
            end

            responses.each do |response|
              # if response is not a hash, skip with error message
              unless response.is_a?(Hash)
                pp response
                next
              end

              if response.key?("type") && response["type"] == "error"
                # Extract error message if available, otherwise use the full response
                error_content = if response.key?("content") && !response["content"].to_s.empty?
                                 response["content"].to_s
                               else
                                 "API Error: " + response.to_s
                               end
                @channel.push({ "type" => "error", "content" => error_content }.to_json)
              else
                unless response.dig("choices", 0, "message", "content")
                  @channel.push({ "type" => "error", "content" => "Content not found in response" }.to_json)
                  break
                end

                # Get raw content
                raw_content = response.dig("choices", 0, "message", "content")
                if raw_content
                  # Fix sandbox URL paths with a more precise regex that ensures we only replace complete paths
                  content = raw_content.gsub(%r{\bsandbox:/([^\s"'<>]+)}, '/\1')
                  # Fix mount paths in the same way
                  content = content.gsub(%r{^/mnt/([^\s"'<>]+)}, '/\1')
                else
                  content = ""
                  @channel.push({ "type" => "error", "content" => "Empty response from API" }.to_json)
                end

                response.dig("choices", 0, "message")["content"] = content

                if obj["auto_speech"] && obj["monadic"]
                  message = JSON.parse(content)["message"]
                  res_hash = tts_api_request(message,
                                            provider: provider,
                                            voice: voice,
                                            speed: speed,
                                            response_format: response_format)
                  @channel.push(res_hash.to_json)
                end

                queue.push(response)
              end
            end
          end
        end
        end

      ws.on :close do |event|
        pp [:close, event.code, event.reason]
        ws = nil
        @channel.unsubscribe(sid)
      end

      ws.rack_response
    end
  rescue StandardError => e
    # show the details of the error on the console
    puts e.inspect
    puts e.backtrace
  end
end
