# frozen_string_literal: true

# Streaming query handler for WebSocket connections.
# Handles the main LLM streaming flow: fragment processing, realtime TTS
# buffering, post-completion TTS, response parsing, and context extraction.
#
# Also includes token counting and message analysis utilities used
# during streaming.

module WebSocketHelper
  # Background thread for token counting using native tokenizer.
  # @param text [String] Text to count tokens for
  # @param encoding_name [String] Encoding name (default: o200k_base)
  # @return [Thread, nil] The counting thread, or nil if text is empty
  def initialize_token_counting(text, encoding_name = "o200k_base")
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

        # Do the actual token counting - uses the caching mechanism in Tokenizer
        result = MonadicApp::TOKENIZER.count_tokens(text, encoding_name)

        # Store for later use in check_past_messages
        Thread.current[:token_count_result] = result
      rescue StandardError => e
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

  # Check if the total tokens of past messages is less than max_tokens in obj.
  # Token count is calculated using tiktoken via Flask tokenizer.
  # @param obj [Hash] Parameters including max_input_tokens, context_size, app_name
  # @return [Hash] Token count statistics and message status
  def check_past_messages(obj)
    # filter out any messages of type "search"
    # Filter messages by current app_name to prevent cross-app conversation leakage
    current_app_name = obj["app_name"] || session.dig("parameters", "app_name") || session.dig(:parameters, "app_name")
    messages = session[:messages].filter { |m| m["type"] != "search" && m["app_name"] == current_app_name }

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

      # Now process any messages that still need token counts
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

  # Calculate the turn number for an assistant message.
  # Turn numbers are 1-indexed based on assistant message order.
  # @param messages [Array] The messages array
  # @param message_index [Integer] The index of the message
  # @return [Integer, nil] The turn number or nil if not an assistant message
  def calculate_turn_number(messages, message_index)
    return nil unless messages && message_index

    message = messages[message_index]
    return nil unless message && message["role"] == "assistant"

    # Count assistant messages up to and including this one
    turn = 0
    messages.each_with_index do |m, idx|
      turn += 1 if m["role"] == "assistant"
      return turn if idx == message_index
    end
    nil
  end

  # Get context schema from session.
  # @param rack_session [Hash] The session
  # @return [Hash, nil] The context schema or nil
  def get_context_schema(rack_session)
    monadic_state = rack_session[:monadic_state] || rack_session["monadic_state"]
    return nil unless monadic_state

    monadic_state[:context_schema] || monadic_state["context_schema"]
  end

  # Main streaming handler — processes LLM API responses with realtime TTS,
  # fragment buffering, post-completion TTS, and context extraction.
  # @return [Thread] The streaming thread (returned for orchestrator control)
  private def handle_ws_streaming(connection, obj, session, queue)
    # Get session ID for targeted broadcasting throughout streaming
    ws_session_id = Thread.current[:websocket_session_id]

    session[:parameters].merge! obj

    # Start background token counting for the user message immediately
    message_text = obj["message"].to_s
    if !message_text.empty?
      # Use o200k_base encoding for most LLMs
      token_count_thread = initialize_token_counting(message_text, "o200k_base")
      Thread.current[:token_count_thread] = token_count_thread

      # Add user message to session for context extraction
      params = get_session_params
      user_message_data = {
        "mid" => SecureRandom.hex(4),
        "role" => "user",
        "text" => message_text,
        "app_name" => params["app_name"],
        "active" => true
      }
      session[:messages] << user_message_data
      sync_session_state!
    end

    # Extract TTS parameters if auto_speech is enabled
    # Convert string "true" to boolean true for compatibility
    obj["auto_speech"] = true if obj["auto_speech"] == "true"

    # Get auto_tts_realtime_mode setting
    # TEMPORARILY DISABLED (2025-11-07): Realtime mode has a race condition where
    # LLM streaming can split words mid-character (e.g., "チャット" → "チャ" + "ット"),
    # causing the sentence segmenter to mark sentences as "complete" before all characters
    # arrive. This results in truncated TTS audio (e.g., "チャット" → "チャ").
    # Need to add fragment stabilization (wait 50-100ms after sentence boundary)
    # before re-enabling.
    # auto_tts_realtime_mode = obj["auto_tts_realtime_mode"]
    # if auto_tts_realtime_mode.nil?
    #   auto_tts_realtime_mode = defined?(CONFIG) && CONFIG["AUTO_TTS_REALTIME_MODE"].to_s == "true"
    # end
    auto_tts_realtime_mode = false  # Force POST-COMPLETION mode until race condition is fixed

    if obj["auto_speech"]
      provider = obj["tts_provider"]
      if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
        voice = obj["elevenlabs_tts_voice"]
      elsif provider == "gemini-flash" || provider == "gemini-pro"
        voice = obj["gemini_tts_voice"]
      else
        voice = obj["tts_voice"]
      end
      speed = obj["tts_speed"]
      response_format = "mp3"
      model = if defined?(Monadic::Utils::ModelSpec)
                Monadic::Utils::ModelSpec.default_tts_model("openai")
              end
      language = obj["conversation_language"] || "auto"
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
        rescue StandardError => e
          # Log error but continue operation
          if defined?(logger) && logger && CONFIG["EXTRA_LOGGING"]
            logger.warn "Token counting error in WebSocket handler: #{e.message}"
          end
        end
      end

      buffer = []
      cutoff = false

      # Initialize sequence counter for realtime TTS (once per message)
      @realtime_tts_sequence_counter = 0

      # Initialize short sentence buffer for realtime TTS
      @realtime_tts_short_buffer = []

      # Save original auto_speech and monadic values before they might be overwritten
      # These will be used for final segment processing after streaming completes
      original_auto_speech = obj["auto_speech"]
      original_monadic = obj["monadic"]

      app_name = obj["app_name"]
      app_obj = APPS[app_name]

      unless app_obj
        error_msg = "App '#{app_name}' not found in APPS"
        puts "[ERROR] #{error_msg}"
        error_message = { "type" => "error", "content" => error_msg }.to_json
        send_or_broadcast(error_message, ws_session_id)
        next
      end

      prev_texts_for_tts = []
      responses = app_obj.api_request("user", session) do |fragment|
        # DEBUG: Log all fragment arrivals
        Monadic::Utils::ExtraLogger.log { "[DEBUG] Fragment arrived: type='#{fragment["type"]}', auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}" }

        if fragment["type"] == "error"
          error_content = fragment["content"] || fragment.to_s
          fragment_error = { "type" => "error", "content" => error_content }.to_json
          send_or_broadcast(fragment_error, ws_session_id)
          break
        elsif fragment["type"] == "clear_fragments"
          # Clear server-side buffers before post-tool response streaming
          # This prevents pre-tool text from being concatenated with post-tool response
          buffer.clear
          @realtime_tts_short_buffer.clear if @realtime_tts_short_buffer

          # Send clear_fragments to frontend to clear the UI temp-card
          clear_msg = { "type" => "clear_fragments" }.to_json
          send_or_broadcast(clear_msg, ws_session_id)

          Monadic::Utils::ExtraLogger.log { "[DEBUG] clear_fragments: server buffers cleared, message sent to frontend" }
        elsif fragment["type"] == "fragment"
          text = fragment["content"]
          buffer << text unless text.empty? || text == "DONE"

          segments = WebSocketHelper.segment_sentences(buffer.join)

          Monadic::Utils::ExtraLogger.log {
            msg = "[DEBUG] Fragment received: buffer_text='#{buffer.join[0..100]}...', segments=#{segments.size}"
            segments.each_with_index do |seg, i|
              msg += "\n[DEBUG]   segment[#{i}]: '#{seg[0..50]}...'"
            end
            msg
          }

          # Wait for complete sentences: TwitterCLDR returns 2+ segments when a sentence is complete
          # Process all complete sentences (all except the last incomplete one)
          if !cutoff && segments.size >= 2
            complete_sentences = segments[0...-1]

            if auto_tts_realtime_mode
              # REALTIME MODE: Use http.rb async processing for non-blocking TTS
              Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE ACTIVE: auto_speech=#{obj["auto_speech"]}, cutoff=#{cutoff}, monadic=#{obj["monadic"]}, segments=#{segments.size}\n[DEBUG] complete_sentences count: #{segments[0...-1].size}" }

              # Process each complete sentence with buffering for short sentences
              # This prevents pauses between short and long sentence TTS generation
              complete_sentences.each_with_index do |sentence, idx|
                split = sentence.split("---")
                if split.empty?
                  cutoff = true
                  break
                end

                # Process sentence fragments for TTS if auto_speech is enabled
                if obj["auto_speech"] && !cutoff && !obj["monadic"]
                  text = split[0] || ""

                  # Strip Markdown markers and HTML tags before TTS processing
                  text = StringUtils.strip_markdown_for_tts(text)

                  # Filter out very short or emoji-only segments
                  cleaned_text = text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                  cleaned_text = cleaned_text.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                  cleaned_text = cleaned_text.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                  cleaned_text = cleaned_text.strip

                  Monadic::Utils::ExtraLogger.log { "[BUFFER] ============================================\n[BUFFER] Sentence #{idx} received\n[BUFFER] Original text: '#{text}'\n[BUFFER] Cleaned text: '#{cleaned_text}'\n[BUFFER] Cleaned length: #{cleaned_text.length}" }

                  # Skip only if text is empty
                  if text.strip != ""
                    # Check if this is a short sentence (≤REALTIME_TTS_MIN_LENGTH chars cleaned length)
                    if cleaned_text.length <= REALTIME_TTS_MIN_LENGTH
                      # Buffer short sentence instead of sending immediately
                      @realtime_tts_short_buffer << text

                      # Calculate total buffer length
                      total_buffer_length = @realtime_tts_short_buffer.map do |buffered_text|
                        cleaned = buffered_text.gsub(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
                        cleaned = cleaned.gsub(/^\s*[-*]\s+/, '').gsub(/^\s*\d+\.\s+/, '')
                        cleaned = cleaned.gsub(/[^\p{L}\p{N}\p{P}\p{Z}]+/, ' ')
                        cleaned.strip.length
                      end.sum

                      Monadic::Utils::ExtraLogger.log {
                        msg = "[BUFFER] Decision: BUFFERING (≤#{REALTIME_TTS_MIN_LENGTH} chars)\n[BUFFER] Buffer size: #{@realtime_tts_short_buffer.size} sentence(s)\n[BUFFER] Total buffer length: #{total_buffer_length} chars\n[BUFFER] Buffer contents:"
                        @realtime_tts_short_buffer.each_with_index do |buf_text, buf_idx|
                          msg += "\n[BUFFER]   [#{buf_idx}]: '#{buf_text}'"
                        end
                        msg
                      }

                      # Check if total buffer length exceeds threshold
                      # This prevents long pauses while maintaining gap prevention
                      if total_buffer_length > REALTIME_TTS_MIN_LENGTH
                        # Flush buffer when accumulated length is sufficient
                        # Add space between sentences to prevent words from merging
                        combined_text = @realtime_tts_short_buffer.join(" ")
                        @realtime_tts_short_buffer.clear

                        Monadic::Utils::ExtraLogger.log { "[BUFFER] *** FLUSHING BUFFER (total: #{total_buffer_length} > #{REALTIME_TTS_MIN_LENGTH}) ***\n[BUFFER] Combined text to send to TTS: '#{combined_text}'\n[BUFFER] Combined text length: #{combined_text.length}" }

                        # Increment counters and create sequence ID
                        @realtime_tts_sequence_counter += 1
                        sequence_num = @realtime_tts_sequence_counter
                        sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                        # Submit TTS request immediately
                        Async do
                          tts_api_request_async(
                            combined_text,
                            provider: provider,
                            voice: voice,
                            speed: speed,
                            response_format: response_format,
                            language: language,
                            sequence_id: sequence_id
                          ) do |res_hash|
                            if res_hash && res_hash["type"] != "error"
                              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS async callback (flushed buffer): sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }
                              # Use captured ws_session_id from outer scope
                              if ws_session_id
                                WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
                              else
                                WebSocketHelper.broadcast_to_all(res_hash.to_json)
                              end
                            else
                              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for flushed buffer: #{res_hash&.[]("content")}" }
                            end
                          end
                        end
                      end
                    else
                      # This is a longer sentence - flush buffer and send combined text
                      Monadic::Utils::ExtraLogger.log { "[BUFFER] Decision: IMMEDIATE SEND (>#{REALTIME_TTS_MIN_LENGTH} chars)\n[BUFFER] Current buffer has #{@realtime_tts_short_buffer.size} sentence(s)" }

                      combined_text = if @realtime_tts_short_buffer.empty?
                                       text
                                     else
                                       # Combine buffered short sentences with current sentence
                                       # Add space between sentences to prevent words from merging
                                       buffered = @realtime_tts_short_buffer.join(" ")
                                       @realtime_tts_short_buffer.clear
                                       "#{buffered} #{text}"
                                     end

                      # Increment counters and create sequence ID
                      @realtime_tts_sequence_counter += 1
                      sequence_num = @realtime_tts_sequence_counter
                      sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

                      Monadic::Utils::ExtraLogger.log { "[BUFFER] *** SENDING TO TTS (long sentence) ***\n[BUFFER] Sequence: #{sequence_num}, ID: #{sequence_id}\n[BUFFER] Combined text to send: '#{combined_text}'\n[BUFFER] Combined text length: #{combined_text.length}" }

                      # Submit TTS request immediately
                      Async do
                        tts_api_request_async(
                          combined_text,
                          provider: provider,
                          voice: voice,
                          speed: speed,
                          response_format: response_format,
                          language: language,
                          sequence_id: sequence_id
                        ) do |res_hash|
                          # This callback runs when TTS completes
                          if res_hash && res_hash["type"] != "error"
                            Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS async callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }

                            # Send audio to client (use captured ws_session_id)
                            if ws_session_id
                              WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
                            else
                              WebSocketHelper.broadcast_to_all(res_hash.to_json)
                            end
                          else
                            # TTS failed, just log it (fragment already sent)
                            Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for segment: #{res_hash&.[]("content")}" }
                          end
                        end
                      end
                    end
                  end
                end
              end

              # REALTIME MODE: Keep the last incomplete sentence in buffer
              buffer = [segments.last]

              # Send the fragment to display text (after TTS processing)
              send_or_broadcast(fragment.to_json, ws_session_id)
            else
              # POST-COMPLETION MODE: Just send fragments, keep everything in buffer
              send_or_broadcast(fragment.to_json, ws_session_id)
            end
          else
            # Just send the fragment without TTS processing
            send_or_broadcast(fragment.to_json, ws_session_id)
          end
        else
          # Handle other fragment types (including html, message, etc.)
          Monadic::Utils::ExtraLogger.log { "[WebSocket] Forwarding fragment type='#{fragment["type"]}' to frontend" }
          send_or_broadcast(fragment.to_json, ws_session_id)
        end
        sleep 0.001  # Reduced from 0.01 for faster streaming
      end

      Thread.exit if !responses || responses.empty?

      # Process final segment for realtime mode
      # The last incomplete sentence in buffer needs to be processed after streaming completes
      # Check both auto_speech and auto_tts_realtime_mode to ensure TTS is intentionally enabled
      # auto_speech can be boolean true or string "true" from client
      # Use original_auto_speech saved before streaming started (obj may have been overwritten)
      auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Checking final segment conditions:\n[DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled}\n[DEBUG]   cutoff=#{cutoff}, original_monadic=#{original_monadic}, auto_tts_realtime_mode=#{auto_tts_realtime_mode}\n[DEBUG]   Buffer contents: #{buffer.inspect}\n[DEBUG]   Short buffer: #{@realtime_tts_short_buffer.inspect}" }

      if auto_speech_enabled && auto_tts_realtime_mode && !cutoff && !original_monadic
        # Prefer the provider-returned full text when available to avoid token loss
        final_text = responses.last && responses.last["text"] ? responses.last["text"].to_s.strip : ""

        # Fallback to buffered join if full text is not present
        if final_text.empty?
          final_text = buffer.join.strip
        end

        Monadic::Utils::ExtraLogger.log { "[DEBUG] Final text from buffer: '#{final_text}'" }

        # Also check if there are any buffered short sentences that haven't been sent yet
        if !@realtime_tts_short_buffer.empty?
          # Combine buffered short sentences with final text
          # Add space between sentences to prevent words from merging
          buffered = @realtime_tts_short_buffer.join(" ")
          final_text = if final_text.empty?
                        buffered
                      else
                        "#{buffered} #{final_text}"
                      end
          @realtime_tts_short_buffer.clear

          Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE: Flushing buffered short sentences into final segment" }
        end

        if final_text != ""
          Monadic::Utils::ExtraLogger.log { "[DEBUG] REALTIME MODE: Processing final segment: '#{final_text[0..50]}...' (length=#{final_text.length})" }

          # Generate unique sequence ID for final segment (use same format as streaming segments)
          # Counter should already be initialized by streaming loop above
          @realtime_tts_sequence_counter += 1
          sequence_num = @realtime_tts_sequence_counter
          sequence_id = "seq#{sequence_num}_#{Time.now.to_f}_#{SecureRandom.hex(2)}"

          # Call async TTS for final segment
          tts_api_request_async(
            final_text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language,
            sequence_id: sequence_id
          ) do |res_hash|
            if res_hash && res_hash["type"] != "error"
              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS final segment callback: sequence_id=#{sequence_id}, type=#{res_hash["type"]}" }
              # Use captured ws_session_id from outer scope
              if ws_session_id
                WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
              else
                WebSocketHelper.broadcast_to_all(res_hash.to_json)
              end
            else
              Monadic::Utils::ExtraLogger.log { "[DEBUG] TTS failed for final segment: #{res_hash&.[]("content")}" }
            end
          end
        end
      end

      # Post-completion TTS processing when realtime mode is FALSE
      # Use original_auto_speech (saved before fragment loop) because obj may be overwritten
      # Convert string "true" to boolean true for compatibility
      auto_speech_enabled = original_auto_speech == true || original_auto_speech == "true"

      # Check if monadic is nil or empty string (both should be treated as false/disabled)
      monadic_disabled = original_monadic.nil? || original_monadic.to_s.strip.empty?

      # Check for tts_target extracted text (for monadic apps like Voice Interpreter)
      # This must be checked BEFORE the condition so monadic apps with tts_target can use TTS
      tts_text_from_target = session[:tts_text]

      # TTS is allowed if auto_speech is enabled, not cutoff, and not realtime mode
      # The actual text source is determined later:
      # - If tts_text_from_target exists (tool was called), use that
      # - Otherwise, fall back to buffer.join (works for all apps including monadic)
      #
      # NOTE: The server auto-triggers TTS here. The client should NOT also click
      # the Play button to avoid duplicate audio playback. The client-side code
      # in websocket.js has been updated to skip playButton.click() when Auto TTS
      # is expected (server will send audio automatically).
      tts_allowed = auto_speech_enabled && !cutoff && !auto_tts_realtime_mode

      Monadic::Utils::ExtraLogger.log { "[DEBUG] POST-COMPLETION MODE conditions:\n[DEBUG]   original_auto_speech=#{original_auto_speech.inspect}, auto_speech_enabled=#{auto_speech_enabled.inspect}\n[DEBUG]   cutoff=#{cutoff.inspect}\n[DEBUG]   original_monadic=#{original_monadic.inspect}, monadic_disabled=#{monadic_disabled.inspect}\n[DEBUG]   auto_tts_realtime_mode=#{auto_tts_realtime_mode.inspect}\n[DEBUG]   tts_text_from_target=#{tts_text_from_target ? 'present' : 'nil'}\n[DEBUG]   tts_allowed=#{tts_allowed.inspect}" }

      if tts_allowed
        # Stop any existing TTS thread first
        if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
          @tts_thread.kill
          @tts_thread = nil
        end

        # Get TTS text: prefer tts_target extraction (from session[:tts_text]) over full buffer
        # This allows apps to specify a specific tool parameter for TTS instead of the full response
        text = tts_text_from_target || buffer.join

        # Clear session tts_text after use to avoid reusing on next request
        session.delete(:tts_text) if tts_text_from_target

        Monadic::Utils::ExtraLogger.log { "[DEBUG] POST-COMPLETION TTS: Using #{tts_text_from_target ? 'tts_target extracted text' : 'buffer.join'}" }

        # Only process if there's actual text
        if text.strip != ""
          start_tts_playback(
            text: text,
            provider: provider,
            voice: voice,
            speed: speed,
            response_format: response_format,
            language: language,
            ws_session_id: ws_session_id
          )
        end
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Processing #{responses&.length || 0} responses\n[DEBUG] responses.nil?=#{responses.nil?}, responses.empty?=#{responses&.empty?}" }

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
          api_error_message = { "type" => "error", "content" => error_content }.to_json
          send_or_broadcast(api_error_message, ws_session_id)
        else
          # Debug logging for response structure (only with EXTRA_LOGGING)
          Monadic::Utils::ExtraLogger.log { "WebSocket response structure:\nResponse class: #{response.class}\nResponse keys: #{response.is_a?(Hash) ? response.keys.inspect : 'N/A'}\nHas choices?: #{response.is_a?(Hash) ? response.key?("choices") : 'N/A'}\nResponse: #{response.inspect[0..500]}..." }

          # Check for content in standard format or responses API format
          raw_content = nil

          # Try standard format first
          raw_content = response.dig("choices", 0, "message", "content")

          # If not found, try responses API format
          if raw_content.nil? && response["output"]
            Monadic::Utils::ExtraLogger.log { "Trying responses API format. Output items: #{response["output"].length}" }

            # Look for message type in output array
            response["output"].each do |item|
              Monadic::Utils::ExtraLogger.log { "Output item type: #{item["type"]}, has content?: #{item.key?("content")}" }

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

            Monadic::Utils::ExtraLogger.log { "Extracted content length: #{raw_content&.length || 0}" }
          end

          # If still no content found
          if raw_content.nil?
            Monadic::Utils::ExtraLogger.log { "ERROR: Content not found. Response structure: #{response.inspect[0..300]}..." }
            content_error = { "type" => "error", "content" => "content_not_found" }.to_json
            send_or_broadcast(content_error, ws_session_id)
            break
          end
          # Fix sandbox URL paths with a more precise regex that ensures we only replace complete paths
          content = raw_content.gsub(%r{\bsandbox:/([^\s"'<>]+)}, '/\1')
          # Fix mount paths in the same way
          content = content.gsub(%r{^/mnt/([^\s"'<>]+)}, '/\1')

          response.dig("choices", 0, "message")["content"] = content

          # Note: TTS for Session State apps is handled via tts_target feature
          # which extracts text from tool parameters (e.g., save_response message)
          # and stores it in session[:tts_text], processed earlier in the pipeline

          queue.push(response)
        end
      end

      Monadic::Utils::ExtraLogger.log { "[DEBUG] Finished processing responses loop" }

      # Send streaming complete message after all responses are processed (session-targeted)
      Monadic::Utils::ExtraLogger.log { "[DEBUG] About to send streaming_complete for session: #{ws_session_id}" }
      streaming_complete = { "type" => "streaming_complete" }.to_json
      send_or_broadcast(streaming_complete, ws_session_id)
      Monadic::Utils::ExtraLogger.log { "[DEBUG] streaming_complete sent successfully" }
    end
    thread  # return the thread for the orchestrator
  end
end
