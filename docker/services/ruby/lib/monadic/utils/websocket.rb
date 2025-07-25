# frozen_string_literal: true

require 'timeout'
require_relative '../agents/ai_user_agent'
require_relative 'boolean_parser'

module WebSocketHelper
  include AIUserAgent
  # Handle websocket connection
  
  # Class variable to store WebSocket connections with thread safety
  @@ws_connections = []
  @@ws_mutex = Mutex.new
  
  # Add a connection to the list (thread-safe)
  def self.add_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections << ws unless @@ws_connections.include?(ws)
    end
  end
  
  # Remove a connection from the list (thread-safe)
  def self.remove_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections.delete(ws)
    end
  end
  
  # Broadcast MCP status to all connected clients (thread-safe)
  def self.broadcast_mcp_status(status)
    message = {
      event: "mcp_status",
      data: status
    }.to_json
    
    # Create a copy of connections to avoid holding lock during I/O
    connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }
    
    connections_copy.each do |ws|
      begin
        # Check if WebSocket is open (Faye::WebSocket uses ready_state)
        if ws && ws.ready_state == Faye::WebSocket::OPEN
          ws.send(message)
        end
      rescue => e
        # Log WebSocket send error and remove dead connection
        puts "[WebSocket] Send error: #{e.message}" if CONFIG["EXTRA_LOGGING"]
        remove_connection(ws)
      end
    end
  end
  
  # Initialize token counting in a background thread
  def initialize_token_counting(text, encoding_name="o200k_base")
    # Return immediately if no text
    return nil if text.nil? || text.empty?
    
    # Store in thread local variable to avoid creating too many threads
    Thread.current[:token_count_in_progress] = true
    
    # Use Thread.new with lower priority to avoid impacting TTS
    Thread.new do
      result = nil
      begin
        # Add a small delay to prioritize TTS thread startup if running concurrently
        sleep 0.05 if Thread.list.any? { |t| t[:type] == :tts }
        
        # Set thread type for identification
        Thread.current[:type] = :token_counter
        
        # Do the actual token counting - this now uses the caching mechanism
        # in FlaskAppClient for better performance
        result = MonadicApp::TOKENIZER.count_tokens(text, encoding_name)
        
        # Store for later use in check_past_messages
        Thread.current[:token_count_result] = result
      rescue => e
        # Log token counting errors for debugging
        if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
          logger.warn "Token counting error: #{e.message}"
        end
        # Continue without blocking the operation
      ensure
        Thread.current[:token_count_in_progress] = false
      end
      
      # Thread's return value
      result
    end
  end

  # check if the total tokens of past messages is less than max_tokens in obj
  # token count is calculated using tiktoken
  def check_past_messages(obj)
    # filter out any messages of type "search"
    messages = session[:messages].filter { |m| m["type"] != "search" }

    res = false
    max_input_tokens = obj["max_input_tokens"].to_i
    context_size = obj["context_size"].to_i
    tokenizer_available = true

    # Default to o200k_base encoding for GPT models
    encoding_name = "o200k_base"

    begin
      # Batch process messages that need token counting to reduce HTTP requests
      messages_to_count = []
      messages.each do |m|
        # Skip messages that already have token counts
        next if m["tokens"]
        
        # If this is the most recent message and we have precounted tokens, use them
        if m == messages.last && defined?(Thread.current[:token_count_result]) && Thread.current[:token_count_result]
          m["tokens"] = Thread.current[:token_count_result]
        else
          # Otherwise add to batch for counting
          messages_to_count << m
        end
        
        # Mark all messages as active initially
        m["active"] = true
      end
      
      # Now process any messages that still need token counts - these use the cache in FlaskAppClient
      messages_to_count.each do |m|
        m["tokens"] = MonadicApp::TOKENIZER.count_tokens(m["text"], encoding_name)
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
      STDERR.puts "Error in token counting: #{e.message}"
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
      
      begin
        parsed_voices = JSON.parse(voices)
      rescue JSON::ParserError => e
        DebugHelper.debug("Invalid JSON from ElevenLabs API: #{voices[0..200]}", "api", level: :error)
        return []
      end
      
      parsed_voices&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end || []
    rescue Net::ReadTimeout => e
      DebugHelper.debug("Timeout reading ElevenLabs voices", "api", level: :warning)
      []
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
    
    # Send MCP server status if available
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      ws.send({ "type" => "mcp_status", "content" => mcp_status }.to_json)
    end
    
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
        # Debug log for JupyterNotebookClaude reasoning_effort
        if k == "JupyterNotebookClaude" && p == "reasoning_effort" && CONFIG["EXTRA_LOGGING"]
          extra_log = File.open(MonadicApp::EXTRA_LOG_FILE, "a")
          extra_log.puts("[#{Time.now}] WebSocket: JupyterNotebookClaude reasoning_effort = #{m.inspect}")
          extra_log.close
        end
        # Special case for models array to ensure it's properly sent as JSON
        if p == "models" && m.is_a?(Array)
          apps[k][p] = m.to_json
        elsif p == "tools" && (m.is_a?(Array) || m.is_a?(Hash))
          # Tools need to be sent as proper JSON too
          apps[k][p] = m.to_json
        elsif p == "disabled"
          # Keep disabled as a string for compatibility with frontend
          apps[k][p] = m.to_s
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
    
    # Send Gemini voices if API key is available
    if CONFIG["GEMINI_API_KEY"]
      gemini_voices = [
        { "voice_id" => "aoede", "name" => "Aoede" },
        { "voice_id" => "charon", "name" => "Charon" },
        { "voice_id" => "fenrir", "name" => "Fenrir" },
        { "voice_id" => "kore", "name" => "Kore" },
        { "voice_id" => "orus", "name" => "Orus" },
        { "voice_id" => "puck", "name" => "Puck" },
        { "voice_id" => "schedar", "name" => "Schedar" },
        { "voice_id" => "zephyr", "name" => "Zephyr" }
      ]
      @channel.push({ "type" => "gemini_voices", "content" => gemini_voices }.to_json)
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
      
      # Update images if provided in the edit request
      if obj["images"] && obj["images"].is_a?(Array)
        message_to_edit["images"] = obj["images"]
      end
      
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
      
      # Include images if they exist
      if message_to_edit["images"] && message_to_edit["images"].is_a?(Array) && !message_to_edit["images"].empty?
        response["images"] = message_to_edit["images"]
      end
      
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
        # Add connection to the list for MCP broadcasting
        WebSocketHelper.add_connection(ws)
      end

      ws.on :message do |event|
        # Websocket message logging removed for performance
        
        begin
          obj = JSON.parse(event.data)
          # Normalize boolean values from JavaScript
          obj = BooleanParser.parse_hash(obj)
        rescue JSON::ParserError => e
          DebugHelper.debug("Invalid JSON in WebSocket message: #{event.data[0..100]}", "websocket", level: :error)
          @channel.push({ "type" => "error", "content" => "Invalid message format received" }.to_json)
          next
        end
        
        msg = obj["message"] || ""
        
        # Debug logging for research assistant apps
        if obj["app_name"] && (obj["app_name"].include?("Perplexity") || obj["app_name"].include?("DeepSeek"))
          puts "[DEBUG WebSocket] Received message type: #{msg.inspect}"
          puts "[DEBUG WebSocket] App name from obj: #{obj["app_name"]}"
        end
        
        case msg
        when "TTS"
          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          
          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            res_hash = { "type" => "web_speech", "content" => text }
          else
            # Generate TTS content for other providers
            puts "TTS: About to call tts_api_request with voice='#{voice}', provider='#{provider}'"
            res_hash = tts_api_request(text,
                                      provider: provider,
                                      voice: voice,
                                      speed: speed,
                                      response_format: response_format)
          end
          @channel.push(res_hash.to_json)
        when "TTS_STREAM"
          thread&.join
          provider = obj["provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual"
            voice = obj["elevenlabs_voice"]
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_voice"]
          else
            voice = obj["voice"]
          end
          text = obj["text"]
          elevenlabs_voice = obj["elevenlabs_voice"]
          speed = obj["speed"]
          response_format = obj["response_format"]
          # model = obj["model"]
          
          
          # Special handling for Web Speech API
          if provider == "webspeech" || provider == "web-speech"
            # Create a special response for Web Speech API
            web_speech_response = { "type" => "web_speech", "content" => text }
            @channel.push(web_speech_response.to_json)
          else
            # Generate TTS content for other providers
            tts_api_request(text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format) do |fragment|
              @channel.push(fragment.to_json)
          end
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
        when "UPDATE_MCP_CONFIG"
          handle_mcp_config_update(ws, obj)
        when "AI_USER_QUERY"
          # Check if there are enough messages for AI User to work with
          if session[:messages].nil? || session[:messages].size < 2
            @channel.push({ 
              "type" => "error", 
              "content" => "AI User requires an existing conversation. Please start a conversation first." 
            }.to_json)
            next
          end
          
          thread&.join
          
          # Get parameters
          params = obj["contents"]["params"]
          
          # UI feedback
          @channel.push({ "type" => "wait", "content" => "Generating AI user response..." }.to_json)
          @channel.push({ "type" => "ai_user_started" }.to_json)
          
          # Process the request
          begin
            # Get AI user response
            result = process_ai_user(session, params)
            
            # Handle result
            if result["type"] == "error"
              @channel.push({ "type" => "error", "content" => result["content"] }.to_json)
            else
              # Send response to client
              @channel.push({ "type" => "ai_user", "content" => result["content"] }.to_json)
              @channel.push({ "type" => "ai_user_finished", "content" => result["content"] }.to_json)
            end
          rescue => e
            # Error handling
            @channel.push({ "type" => "error", "content" => "AI User error: #{e.message}" }.to_json)
          end
        when "HTML"
          thread&.join
          until queue.empty?
            last_one = queue.shift
            begin
              content = last_one["choices"][0]

              # Always use message content - monadic apps will have JSON in content field
              text = content["text"] || content["message"]["content"]
              pp "[DEBUG] WebSocket - text extraction: content keys = #{content.keys}, text = #{text.class}:#{text.to_s[0..100]}..." if session["parameters"]["app_name"]&.include?("Perplexity")
              # Extract thinking content uniformly from message
              thinking = content["message"]["thinking"] || content["message"]["reasoning_content"] || content["thinking"]
              
              # Check if text contains citation HTML that needs to be extracted
              citation_html = nil
              if text && text.include?("<div data-title='Citations'")
                # Extract citation HTML from the text
                if match = text.match(/(\n\n<div data-title='Citations'[^>]*>.*?<\/div>)/m)
                  citation_html = match[1]
                  # Remove citation HTML from text so it doesn't get processed by markdown
                  text = text.sub(match[1], '')
                  
                  if CONFIG["EXTRA_LOGGING"]
                    DebugHelper.debug("WebSocket: Extracted citation HTML from text", category: :api, level: :info)
                    DebugHelper.debug("WebSocket: Citation HTML: #{citation_html[0..100]}...", category: :api, level: :debug)
                  end
                end
              elsif CONFIG["EXTRA_LOGGING"]
                if text && text.match(/\[\d+\]/)
                  DebugHelper.debug("WebSocket: Found citation references but no HTML: #{text.scan(/\[\d+\]/).join(', ')}", category: :api, level: :info)
                end
              end
              

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
              
              # Add citation HTML back after markdown processing
              if citation_html
                html += citation_html
                if CONFIG["EXTRA_LOGGING"]
                  DebugHelper.debug("WebSocket: Added citation HTML to final output", category: :api, level: :info)
                end
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
              STDERR.puts "Error processing request: #{e.message}"
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
          begin
            text = obj["content"]
            images = obj["images"]
            # Generate a unique message ID
            message_id = SecureRandom.hex(4)
            
            # Create message data
            new_data = { 
              "mid" => message_id,
              "role" => obj["role"],
              "text" => text,
              "active" => true 
            }
            
            # Add images if present
            new_data["images"] = images if images
            
            # Format HTML content based on role
            if obj["role"] == "assistant"
              new_data["html"] = markdown_to_html(text)
            else
              # For user and system roles, preserve line breaks
              new_data["html"] = text
            end
            
            # First add to session
            session[:messages] << new_data
            
            # Force the system to send a properly formatted message that will be displayed
            if obj["role"] == "user"
              badge = "<span class='text-secondary'><i class='fas fa-face-smile'></i></span> <span class='fw-bold fs-6 user-color'>User</span>"
              html_content = "<p>" + text.gsub("<", "&lt;").gsub(">", "&gt;").gsub("\n", "<br>").gsub(/\s/, " ") + "</p>"
            elsif obj["role"] == "assistant"
              badge = "<span class='text-secondary'><i class='fas fa-robot'></i></span> <span class='fw-bold fs-6 assistant-color'>Assistant</span>"
              html_content = new_data["html"]
            else # system
              badge = "<span class='text-secondary'><i class='fas fa-bars'></i></span> <span class='fw-bold fs-6 system-color'>System</span>"
              html_content = new_data["html"]
            end
            
            # Send a dedicated message for immediate display
            @channel.push({ 
              "type" => "display_sample", 
              "content" => {
                "mid" => message_id,
                "role" => obj["role"],
                "html" => html_content,
                "badge" => badge
              }
            }.to_json)
            
            # Also send HTML message for session history
            @channel.push({ "type" => "html", "content" => new_data }.to_json)
            
            # Add a success response to confirm message was processed
            @channel.push({ "type" => "sample_success", "role" => obj["role"] }.to_json)
          rescue => e
            # Log the error
            puts "Error processing SAMPLE message: #{e.message}"
            puts e.backtrace
            
            # Inform the client
            @channel.push({ "type" => "error", "content" => "Error processing sample message" }.to_json)
          end
        when "AUDIO"
          handle_audio_message(ws, obj)
        when "STOP_TTS"
          # Stop any running TTS thread
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            @tts_thread.kill
            @tts_thread = nil
            puts "TTS thread stopped by STOP_TTS message"
          end
          
          # Send confirmation
          @channel.push({
            "type" => "tts_stopped"
          }.to_json)
        when "PLAY_TTS"
          # Handle play TTS message
          # This is similar to auto_speech processing but for card playback
          
          # Stop any existing TTS thread first
          if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
            @tts_thread.kill
            @tts_thread = nil
          end
          
          thread&.join
          
          # Extract TTS parameters
          provider = obj["tts_provider"]
          if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual"
            voice = obj["elevenlabs_tts_voice"] 
          elsif provider == "gemini-flash" || provider == "gemini-pro"
            voice = obj["gemini_tts_voice"]
          else
            voice = obj["tts_voice"]
          end
          text = obj["text"]
          speed = obj["tts_speed"]
          response_format = "mp3"
          
          # Process text with PragmaticSegmenter to split into sentences
          ps = PragmaticSegmenter::Segmenter.new(text: text)
          segments = ps.segment
          
          # For Gemini TTS, combine short segments to avoid API failures
          if provider == "gemini-flash" || provider == "gemini-pro"
            combined_segments = []
            current_segment = ""
            
            segments.each do |segment|
              # Clean and check text
              cleaned_text = segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '') # Remove emojis
              cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ') # Remove special chars
              cleaned_text = cleaned_text.strip
              
              if current_segment.empty?
                # Start a new segment
                current_segment = segment
              elsif cleaned_text.length < 8  # Increased threshold for safety
                # Current segment is short, combine with existing
                current_segment += " " + segment
              else
                # Check if current accumulated segment should be finalized
                current_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                current_cleaned = current_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip
                
                if current_cleaned.length < 8  # Combine if still short
                  current_segment += " " + segment
                else
                  # Finalize current segment and start new one
                  combined_segments << current_segment if current_cleaned.length >= 3
                  current_segment = segment
                end
              end
            end
            
            # Don't forget the last segment - but validate it first
            unless current_segment.empty?
              final_cleaned = current_segment.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
              final_cleaned = final_cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ').strip
              combined_segments << current_segment if final_cleaned.length >= 3
            end
            
            segments = combined_segments
            puts "Gemini TTS: #{ps.segment.length} -> #{segments.length} segments" if ENV["DEBUG_TTS"]
          end
          
          # Check if batch processing should be used
          use_batch_processing = defined?(CONFIG) && CONFIG["USE_BATCH_PROCESSING"] != "false"
          
          # Process each segment
          prev_texts_for_tts = []
          
          # Start a new thread for TTS processing
          @tts_thread = Thread.new do
            Thread.current[:type] = :tts_playback
            
            segments.each_with_index do |segment, i|
              # Skip empty segments
              next if segment.strip.empty?
              
              # Light filtering for Gemini TTS
              if provider == "gemini-flash" || provider == "gemini-pro"
                cleaned_segment = segment.strip
                
                # Skip if too short after stripping
                if cleaned_segment.length < 3
                  next
                end
                
                segment = cleaned_segment
              end
              
              # Process this segment
              previous_text = prev_texts_for_tts.empty? ? nil : prev_texts_for_tts[-1]
              
              # Special handling for Web Speech API
              if provider == "webspeech" || provider == "web-speech"
                # Create a special response for Web Speech API
                res_hash = { "type" => "web_speech", "content" => segment }
              else
                # Generate TTS content for other providers
                res_hash = tts_api_request(segment,
                                          previous_text: previous_text, 
                                          provider: provider,
                                          voice: voice,
                                          speed: speed,
                                          response_format: response_format)
                # Add segment information for proper sequencing
                if res_hash && res_hash["type"] == "audio"
                  res_hash["segment_index"] = i
                  res_hash["total_segments"] = segments.length
                  res_hash["is_segment"] = true
                end
              end
              
              # Store for context in next segment
              prev_texts_for_tts << segment
              
              # Create a special message for client to show TTS progress
              progress_message = {
                "type" => "tts_progress",
                "segment_index" => i,
                "total_segments" => segments.length,
                "progress" => ((i + 1) / segments.length.to_f * 100).round
              }
              
              # Send the audio/speech message only if it's valid
              if res_hash && res_hash["type"] != "error"
                @channel.push(res_hash.to_json)
                
                # Send progress update
                @channel.push(progress_message.to_json)
              else
                # Log the error
                puts "TTS segment failed: #{res_hash&.dig("content") || "Unknown error"}"
              end
            end
            
            # Signal completion
            @channel.push({
              "type" => "tts_complete",
              "total_segments" => segments.length
            }.to_json)
          end
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
            if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual"
              voice = obj["elevenlabs_tts_voice"] 
            elsif provider == "gemini-flash" || provider == "gemini-pro"
              voice = obj["gemini_tts_voice"]
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
                # Log timeout and continue without precounted tokens
                if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
                  logger.warn "Token counting timeout - continuing without precount"
                end
              rescue => e
                # Log error but continue operation
                if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
                  logger.warn "Token counting error in WebSocket handler: #{e.message}"
                end
              end
            end
            
            buffer = []
            cutoff = false

            app_name = obj["app_name"]
            app_obj = APPS[app_name]
            
            # Debug logging for troubleshooting
            if app_name && (app_name.include?("Perplexity") || app_name.include?("DeepSeek"))
              puts "[DEBUG WebSocket] Processing message for app: #{app_name}"
              puts "[DEBUG WebSocket] App object found: #{!app_obj.nil?}"
              puts "[DEBUG WebSocket] ChatPlusPerplexity exists: #{APPS.key?("ChatPlusPerplexity")}"
              puts "[DEBUG WebSocket] All Chat Plus apps: #{APPS.keys.select { |k| k.include?("ChatPlus") }}"
              puts "[DEBUG WebSocket] Total apps count: #{APPS.keys.length}"
            end
            
            unless app_obj
              error_msg = "App '#{app_name}' not found in APPS"
              puts "[ERROR] #{error_msg}"
              @channel.push({ "type" => "error", "content" => error_msg }.to_json)
              next
            end

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
                  # Process all complete sentences except the last incomplete one
                  complete_sentences = segments[0...-1]
                  incomplete_sentence = segments[-1]
                  
                  # Process each complete sentence for TTS
                  complete_sentences.each do |sentence|
                    split = sentence.split("---")
                    if split.empty?
                      cutoff = true
                      break
                    end

                    # Check if batch processing should be used
                    # Default to true unless explicitly set to false in config
                    use_batch_processing = defined?(CONFIG) && CONFIG["USE_BATCH_PROCESSING"] != "false"
                    
                    # Process sentence fragments for TTS if auto_speech is enabled
                    if obj["auto_speech"] && !cutoff && !obj["monadic"]
                      text = split[0] || ""
                      if text.strip != ""
                        previous_text = prev_texts_for_tts.empty? ? nil : prev_texts_for_tts[-1]
                        
                        # Generate unique sequence ID for this audio chunk
                        sequence_id = "#{Time.now.to_f}_#{SecureRandom.hex(2)}"
                        
                        # Special handling for Web Speech API
                        if provider == "webspeech" || provider == "web-speech"
                          # Create a special response for Web Speech API
                          res_hash = { "type" => "web_speech", "content" => text, "sequence_id" => sequence_id }
                        else
                          # Generate TTS content for other providers
                          res_hash = tts_api_request(text,
                                                   previous_text: previous_text, 
                                                   provider: provider,
                                                   voice: voice,
                                                   speed: speed,
                                                   response_format: response_format)
                          # Add sequence_id to the result if it's a hash
                          res_hash["sequence_id"] = sequence_id if res_hash.is_a?(Hash)
                        end
                        
                        # Only add to prev_texts if TTS was successful
                        if res_hash && res_hash["type"] != "error"
                          prev_texts_for_tts << text
                          
                          # Use batch processing if enabled
                          if use_batch_processing
                            begin
                              # Send fragment and audio as a combined message
                              # Add auto_speech flag to ensure client knows this should auto-play
                              batch = {
                                "type" => "fragment_with_audio",
                                "fragment" => fragment,
                                "audio" => res_hash,
                                "auto_speech" => true,
                                "sequence_id" => sequence_id
                              }
                              @channel.push(batch.to_json)
                            rescue => e
                              # Fallback to individual messages on error
                              puts "Batch processing error: #{e.message}. Falling back to individual messages."
                              @channel.push(fragment.to_json)
                              @channel.push(res_hash.to_json) if res_hash
                            end
                          else
                            # Use traditional separate messages
                            @channel.push(res_hash.to_json) if res_hash
                            @channel.push(fragment.to_json)
                          end
                        else
                          # TTS failed, just send the fragment
                          @channel.push(fragment.to_json)
                        end
                      else
                        # Empty text, just send the fragment
                        @channel.push(fragment.to_json)
                      end
                    else
                      # No TTS processing needed, just send the fragment
                      @channel.push(fragment.to_json)
                    end
                  end

                  # Keep only the incomplete sentence in the buffer
                  buffer = [incomplete_sentence]
                else
                  # Just send the fragment without TTS processing
                  @channel.push(fragment.to_json)
                end
              else
                # Handle other fragment types
                @channel.push(fragment.to_json)
              end
              sleep 0.01
            end

            Thread.exit if !responses || responses.empty?

            # We play back TTS at the end of processing, regardless of whether 
            # this is a regular message or initiated from assistant
            # Convert string "true" to boolean true for compatibility
            obj["auto_speech"] = true if obj["auto_speech"] == "true"
            
            if obj["auto_speech"] && !cutoff && !obj["monadic"]
              text = buffer.join
              
              # Only process if there's actual text
              if text.strip != ""
                previous_text = prev_texts_for_tts.empty? ? nil : prev_texts_for_tts[-1]
                
                # Generate unique sequence ID for final audio chunk
                sequence_id = "#{Time.now.to_f}_#{SecureRandom.hex(2)}_final"
                
                # Special handling for Web Speech API - no server-side processing needed
                if provider == "webspeech" || provider == "web-speech"
                  # Create a special response for Web Speech API that will be handled client-side
                  res_hash = { "type" => "web_speech", "content" => text, "sequence_id" => sequence_id }
                else
                  # Generate TTS for remaining text with other providers
                  res_hash = tts_api_request(text, 
                                            previous_text: previous_text,
                                            provider: provider, 
                                            voice: voice,
                                            speed: speed,
                                            response_format: response_format)
                  # Add sequence_id to the result if it's a hash
                  res_hash["sequence_id"] = sequence_id if res_hash.is_a?(Hash)
                end
                
                # Check if batch processing should be used
                use_batch_processing = defined?(CONFIG) && CONFIG["USE_BATCH_PROCESSING"] != "false"
                
                if use_batch_processing
                  begin
                    # Create a final fragment with the remaining text
                    final_fragment = {
                      "type" => "fragment",
                      "content" => text,
                      "final" => true
                    }
                    
                    # Send fragment and audio as a combined message
                    batch = {
                      "type" => "fragment_with_audio",
                      "fragment" => final_fragment,
                      "audio" => res_hash,
                      "auto_speech" => true,
                      "final" => true,
                      "sequence_id" => SecureRandom.hex(4) # Add unique ID to track playback
                    }
                    @channel.push(batch.to_json)
                  rescue => e
                    # Fallback to individual message on error
                    puts "Batch processing error: #{e.message}. Falling back to individual messages."
                    @channel.push(res_hash.to_json)
                  end
                else
                  # Use traditional separate message
                  @channel.push(res_hash.to_json)
                end
              end
            end

            responses.each do |response|
              # if response is not a hash, skip with error message
              unless response.is_a?(Hash)
                STDERR.puts "Invalid API response format: #{response.class}"
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
                # Debug logging for response structure (only with EXTRA_LOGGING)
                if CONFIG["EXTRA_LOGGING"]
                  puts "WebSocket response structure:"
                  puts "Response class: #{response.class}"
                  puts "Response keys: #{response.keys.inspect}" if response.is_a?(Hash)
                  puts "Has choices?: #{response.key?("choices") if response.is_a?(Hash)}"
                  puts "Response: #{response.inspect[0..500]}..." # First 500 chars
                end
                
                # Check for content in standard format or responses API format
                raw_content = nil
                
                # Try standard format first
                raw_content = response.dig("choices", 0, "message", "content")
                
                # If not found, try responses API format
                if raw_content.nil? && response["output"]
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Trying responses API format. Output items: #{response["output"].length}"
                  end
                  
                  # Look for message type in output array
                  response["output"].each do |item|
                    if CONFIG["EXTRA_LOGGING"]
                      puts "Output item type: #{item["type"]}, has content?: #{item.key?("content")}"
                    end
                    
                    if item["type"] == "message" && item["content"]
                      # Extract text from content array
                      if item["content"].is_a?(Array)
                        item["content"].each do |content_item|
                          # Handle both "text" and "output_text" types
                          if (content_item["type"] == "text" || content_item["type"] == "output_text") && content_item["text"]
                            raw_content ||= ""
                            raw_content += content_item["text"]
                          end
                        end
                      elsif item["content"].is_a?(String)
                        raw_content = item["content"]
                      end
                    end
                  end
                  
                  if CONFIG["EXTRA_LOGGING"]
                    puts "Extracted content length: #{raw_content&.length || 0}"
                  end
                end
                
                # If still no content found
                if raw_content.nil?
                  puts "ERROR: Content not found. Response structure: #{response.inspect[0..300]}..." if CONFIG["EXTRA_LOGGING"]
                  @channel.push({ "type" => "error", "content" => "Content not found in response" }.to_json)
                  break
                end
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
                  begin
                    parsed_content = JSON.parse(content)
                    message = parsed_content["message"]
                    
                    if message && !message.empty?
                      res_hash = tts_api_request(message,
                                                provider: provider,
                                                voice: voice,
                                                speed: speed,
                                                response_format: response_format)
                      @channel.push(res_hash.to_json) if res_hash
                    end
                  rescue JSON::ParserError => e
                    # Log the error but don't crash
                    puts "[TTS] Failed to parse monadic response for TTS: #{e.message}"
                  end
                end

                queue.push(response)
              end
            end
            
            # Send streaming complete message after all responses are processed
            @channel.push({ "type" => "streaming_complete" }.to_json)
          end
        end
        end

      ws.on :close do |event|
        # Remove connection from the list
        WebSocketHelper.remove_connection(ws)
        ws = nil
        @channel.unsubscribe(sid)
      end

      ws.rack_response
    end
  rescue StandardError => e
    # Error logging handled by main application
  end
  
  # Handle MCP configuration update
  def handle_mcp_config_update(ws, obj)
    # Update configuration
    CONFIG["MCP_SERVER_ENABLED"] = obj["enabled"] # Keep as boolean
    CONFIG["MCP_SERVER_PORT"] = obj["port"] if obj["port"]
    
    # Write updated config to file (optional - depends on persistence requirements)
    # This would require implementing a save_config method
    
    # Send updated MCP server status
    if defined?(Monadic::MCP::Server)
      mcp_status = Monadic::MCP::Server.status
      ws.send({ "type" => "mcp_status", "content" => mcp_status }.to_json)
    end
    
    ws.send({ "type" => "info", "content" => "MCP configuration updated" }.to_json)
  end
end
