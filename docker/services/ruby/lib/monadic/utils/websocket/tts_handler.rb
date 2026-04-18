# frozen_string_literal: true

# Text-to-speech (TTS) operations for WebSocket connections.
# Handles voice listing, TTS request processing, playback control,
# and streaming TTS delivery.

module WebSocketHelper
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
        DebugHelper.debug("Invalid JSON from ElevenLabs API: #{voices[0..200]}", category: :api, level: :error)
        return []
      end

      parsed_voices&.dig("voices")&.map do |voice|
        {
          "voice_id" => voice["voice_id"],
          "name" => voice["name"]
        }
      end || []
    rescue Net::ReadTimeout => e
      DebugHelper.debug("Timeout reading ElevenLabs voices", category: :api, level: :warning)
      []
    rescue StandardError => e
      []
    end
  end

  # Push voice data to WebSocket
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  def push_voice_data(connection)
    elevenlabs_voices = list_elevenlabs_voices
    if elevenlabs_voices && !elevenlabs_voices.empty?
      WebSocketHelper.broadcast_to_all({ "type" => "elevenlabs_voices", "content" => elevenlabs_voices }.to_json)
    end
    
    # Send Gemini voices if API key is available
    # Full list of 30 voices from Gemini TTS API
    if CONFIG["GEMINI_API_KEY"]
      gemini_voices = [
        { "voice_id" => "zephyr", "name" => "Zephyr" },
        { "voice_id" => "puck", "name" => "Puck" },
        { "voice_id" => "charon", "name" => "Charon" },
        { "voice_id" => "kore", "name" => "Kore" },
        { "voice_id" => "fenrir", "name" => "Fenrir" },
        { "voice_id" => "leda", "name" => "Leda" },
        { "voice_id" => "orus", "name" => "Orus" },
        { "voice_id" => "aoede", "name" => "Aoede" },
        { "voice_id" => "callirrhoe", "name" => "Callirrhoe" },
        { "voice_id" => "autonoe", "name" => "Autonoe" },
        { "voice_id" => "enceladus", "name" => "Enceladus" },
        { "voice_id" => "iapetus", "name" => "Iapetus" },
        { "voice_id" => "umbriel", "name" => "Umbriel" },
        { "voice_id" => "algieba", "name" => "Algieba" },
        { "voice_id" => "despina", "name" => "Despina" },
        { "voice_id" => "erinome", "name" => "Erinome" },
        { "voice_id" => "algenib", "name" => "Algenib" },
        { "voice_id" => "rasalgethi", "name" => "Rasalgethi" },
        { "voice_id" => "laomedeia", "name" => "Laomedeia" },
        { "voice_id" => "achernar", "name" => "Achernar" },
        { "voice_id" => "alnilam", "name" => "Alnilam" },
        { "voice_id" => "schedar", "name" => "Schedar" },
        { "voice_id" => "gacrux", "name" => "Gacrux" },
        { "voice_id" => "pulcherrima", "name" => "Pulcherrima" },
        { "voice_id" => "achird", "name" => "Achird" },
        { "voice_id" => "zubenelgenubi", "name" => "Zubenelgenubi" },
        { "voice_id" => "vindemiatrix", "name" => "Vindemiatrix" },
        { "voice_id" => "sadachbia", "name" => "Sadachbia" },
        { "voice_id" => "sadaltager", "name" => "Sadaltager" },
        { "voice_id" => "sulafat", "name" => "Sulafat" }
      ]
      WebSocketHelper.broadcast_to_all({ "type" => "gemini_voices", "content" => gemini_voices }.to_json)
    end

    # Send Mistral voices if API key is available (fetched from API)
    if CONFIG["MISTRAL_API_KEY"]
      mistral_voices = list_mistral_voices
      if mistral_voices && !mistral_voices.empty?
        WebSocketHelper.broadcast_to_all({ "type" => "mistral_voices", "content" => mistral_voices }.to_json)
      end
    end
  end

  # List available Mistral TTS voices
  def list_mistral_voices(api_key = nil)
    api_key ||= CONFIG["MISTRAL_API_KEY"] if defined?(CONFIG)
    return [] unless api_key

    begin
      url = URI("https://api.mistral.ai/v1/audio/voices?limit=50")
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(url)
      request["Authorization"] = "Bearer #{api_key}"
      response = http.request(request)

      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.read_body)
      lang_labels = { "en_us" => "US", "en_gb" => "UK", "fr_fr" => "FR", "de_de" => "DE",
                      "es_es" => "ES", "it_it" => "IT", "pt_pt" => "PT", "zh_cn" => "CN",
                      "ja_jp" => "JP", "ko_kr" => "KR" }
      (data["items"] || [])
        .sort_by { |v| [v["name"].to_s.split(" - ").first, v["name"].to_s.include?("Neutral") ? 0 : 1, v["name"].to_s] }
        .map do |voice|
          lang = (voice["languages"] || []).map { |l| lang_labels[l] || l }.join("/")
          { "voice_id" => voice["id"], "name" => "#{voice["name"]} (#{lang})" }
        end
    rescue StandardError => e
      Monadic::Utils::ExtraLogger.log { "[Mistral] Voice list error: #{e.message}" }
      []
    end
  end

  # Single TTS request for post-completion mode (no sentence splitting)
  # This provides better audio quality with natural flow and intonation
  # @param text [String] Text to convert to speech (whole text, not segmented)
  # @param provider [String] TTS provider
  # @param voice [String] Voice ID
  # @param speed [Float] Speech speed
  # @param response_format [String] Audio format
  # @param language [String] Language code
  # @param ws_session_id [String] WebSocket session ID for targeted broadcasting
  def start_single_tts_request(text:, provider:, voice:, speed:, response_format:, language:, ws_session_id:)
    # Special handling for Web Speech API - no API call needed
    if provider == "webspeech" || provider == "web-speech"
      res_hash = { "type" => "web_speech", "content" => text }
      send_or_broadcast(res_hash.to_json, ws_session_id)

      # Send completion message
      complete_message = { "type" => "tts_complete", "total_segments" => 1 }.to_json
      send_or_broadcast(complete_message, ws_session_id)
      return
    end

    # Start TTS thread for API-based providers
    @tts_thread = Thread.new do
      Thread.current[:type] = :tts_playback

      begin
        res_hash = tts_api_request(text,
                                   previous_text: nil,
                                   provider: provider,
                                   voice: voice,
                                   speed: speed,
                                   response_format: response_format,
                                   language: language)

        if res_hash && res_hash["type"] == "audio"
          res_hash["segment_index"] = 0
          res_hash["total_segments"] = 1
          res_hash["is_segment"] = false  # Not segmented
          res_hash["sequence_id"] = "tts_#{SecureRandom.hex(8)}"

          if ws_session_id
            WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
          else
            WebSocketHelper.broadcast_to_all(res_hash.to_json)
          end

          # Send progress (100% complete)
          progress_message = {
            "type" => "tts_progress",
            "segment_index" => 0,
            "total_segments" => 1,
            "progress" => 100
          }
          send_or_broadcast(progress_message.to_json, ws_session_id)
        else
          # Forward error to frontend so user sees what went wrong
          error_content = res_hash&.dig("content") || "Unknown TTS error"
          puts "[TTS] Single request failed: #{error_content}"
          error_message = { "type" => "error", "content" => error_content }.to_json
          send_or_broadcast(error_message, ws_session_id)
        end
      rescue StandardError => e
        puts "[TTS] Single request exception: #{e.message}"
        Monadic::Utils::ExtraLogger.log { "[TTS] Backtrace: #{e.backtrace[0..3].join("\n")}" }
        # Forward exception as error to frontend
        error_message = { "type" => "error", "content" => "TTS error: #{e.message}" }.to_json
        send_or_broadcast(error_message, ws_session_id)
      end

      # Send completion message
      complete_message = { "type" => "tts_complete", "total_segments" => 1 }.to_json
      send_or_broadcast(complete_message, ws_session_id)
    end
  end

  # Common TTS playback processing for PLAY_TTS and Auto Speech.
  # Synthesizes the full text as a single request; when Auto TTS text exceeds
  # AUTO_TTS_MAX_BYTES, trims at sentence boundaries and notifies the client.
  # @param text [String] Text to convert to speech
  # @param provider [String] TTS provider (e.g., "elevenlabs-v3", "gemini-flash")
  # @param voice [String] Voice ID
  # @param speed [Float] Speech speed
  # @param response_format [String] Audio format (e.g., "aac")
  # @param language [String] Language code
  # @param manual_play [Boolean] If true, this is a manual Play button click - no byte limit applied
  # @param ws_session_id [String, nil] WebSocket session ID for targeted audio delivery
  def start_tts_playback(text:, provider:, voice:, speed:, response_format:, language:, manual_play: false, ws_session_id: nil)
    # Use passed ws_session_id or fall back to thread-local variable
    ws_session_id ||= Thread.current[:websocket_session_id]

    Monadic::Utils::ExtraLogger.log { "[DEBUG] start_tts_playback CALLED: text_length=#{text.length}, provider=#{provider}, manual_play=#{manual_play}" }

    # Strip Markdown markers and HTML tags before processing
    text = StringUtils.strip_markdown_for_tts(text)

    # MANUAL PLAY MODE: User explicitly clicked Play button - no byte limit, play full text
    if manual_play
      total_segments = WebSocketHelper.segment_sentences(text).length

      notice_message = {
        "type" => "tts_notice",
        "content" => {
          "notice_type" => "manual_play",
          "segments_total" => total_segments
        }
      }
      send_or_broadcast(notice_message.to_json, ws_session_id)

      return start_single_tts_request(
        text: text,
        provider: provider,
        voice: voice,
        speed: speed,
        response_format: response_format,
        language: language,
        ws_session_id: ws_session_id
      )
    end

    # Auto TTS path: cap payload with AUTO_TTS_MAX_BYTES, trimming at sentence
    # boundaries when necessary, then send as a single TTS request.
    max_bytes = CONFIG["AUTO_TTS_MAX_BYTES"] || 4000
    text_bytes = text.bytesize

    Monadic::Utils::ExtraLogger.log { "[TTS] Auto TTS: text_bytes=#{text_bytes}, max_bytes=#{max_bytes}" }

    if text_bytes <= max_bytes
      Monadic::Utils::ExtraLogger.log { "[TTS] Text within limit, sending as single request" }
      return start_single_tts_request(
        text: text,
        provider: provider,
        voice: voice,
        speed: speed,
        response_format: response_format,
        language: language,
        ws_session_id: ws_session_id
      )
    end

    Monadic::Utils::ExtraLogger.log { "[TTS] Text exceeds limit (#{text_bytes} > #{max_bytes}), using sentence boundary cutoff" }

    all_segments = WebSocketHelper.segment_sentences(text)

    # Accumulate consecutive segments from the beginning until byte limit is reached
    accumulated_bytes = 0
    tts_segments = []
    skipped_segments = []
    limit_reached = false

    all_segments.each do |segment|
      if limit_reached
        skipped_segments << segment
      else
        segment_bytes = segment.bytesize
        if accumulated_bytes + segment_bytes <= max_bytes
          tts_segments << segment
          accumulated_bytes += segment_bytes
        else
          limit_reached = true
          skipped_segments << segment
        end
      end
    end

    Monadic::Utils::ExtraLogger.log { "[TTS] Sentence boundary cutoff: #{tts_segments.length}/#{all_segments.length} segments included\n[TTS] Accumulated bytes: #{accumulated_bytes}" }

    if tts_segments.any? && skipped_segments.any?
      notice_message = {
        "type" => "tts_notice",
        "content" => {
          "notice_type" => "partial",
          "segments_played" => tts_segments.length,
          "segments_total" => all_segments.length,
          "bytes_played" => accumulated_bytes,
          "bytes_total" => text_bytes
        }
      }
      send_or_broadcast(notice_message.to_json, ws_session_id)
    end

    # If no segments fit within the limit, always include at least the first
    # segment — playing something is better than silence.
    if tts_segments.empty? && all_segments.any?
      first_segment = skipped_segments.shift
      tts_segments << first_segment
      accumulated_bytes = first_segment.bytesize

      Monadic::Utils::ExtraLogger.log { "[TTS] First segment exceeds limit but will be played anyway (#{accumulated_bytes} bytes)" }

      if skipped_segments.any?
        notice_message = {
          "type" => "tts_notice",
          "content" => {
            "notice_type" => "partial",
            "segments_played" => 1,
            "segments_total" => all_segments.length,
            "bytes_played" => accumulated_bytes,
            "bytes_total" => text_bytes
          }
        }
        send_or_broadcast(notice_message.to_json, ws_session_id)
      end
    end

    combined_text = tts_segments.join(" ")
    start_single_tts_request(
      text: combined_text,
      provider: provider,
      voice: voice,
      speed: speed,
      response_format: response_format,
      language: language,
      ws_session_id: ws_session_id
    )
  end


  private def handle_ws_tts(connection, obj, session)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    provider = obj["provider"]
    if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
      voice = obj["elevenlabs_voice"]
    elsif provider == "gemini-flash" || provider == "gemini-pro"
      voice = obj["gemini_voice"]
    elsif provider == "mistral"
      voice = obj["mistral_voice"]
    elsif provider == "grok"
      voice = obj["grok_voice"]
    else
      voice = obj["voice"]
    end
    text = obj["text"]
    elevenlabs_voice = obj["elevenlabs_voice"]
    speed = obj["speed"]
    response_format = obj["response_format"]
    language = obj["conversation_language"] || "auto"

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
                                response_format: response_format,
                                language: language)
      # Add unique ID to prevent false duplicate detection on frontend
      res_hash["sequence_id"] = "tts_#{SecureRandom.hex(8)}" if res_hash&.dig("type") == "audio"
    end

    # Send TTS response to session only
    if ws_session_id
      WebSocketHelper.send_audio_to_session(res_hash.to_json, ws_session_id)
    else
      WebSocketHelper.broadcast_to_all(res_hash.to_json)
    end
  end

  private def handle_ws_stop_tts(connection, obj, session)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Stop any running TTS thread and all prefetch threads
    if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
      # Kill all prefetch subthreads first
      begin
        tts_futures = @tts_thread[:tts_futures]
        if tts_futures && tts_futures.is_a?(Array)
          tts_futures.each do |future_thread|
            future_thread.kill if future_thread && future_thread.alive?
          rescue StandardError => e
            # Already dead or error during kill - safe to ignore
          end
        end
      rescue StandardError => e
        # Error accessing thread locals - continue with main thread cleanup
        Monadic::Utils::ExtraLogger.log { "Error cleaning up TTS subthreads: #{e.message}" }
      end

      # Kill main TTS thread
      @tts_thread.kill
      @tts_thread = nil
      puts "TTS thread and subthreads stopped by STOP_TTS message"
    end

    # Send confirmation
    tts_stopped_message = { "type" => "tts_stopped" }.to_json
    send_or_broadcast(tts_stopped_message, ws_session_id)
  end

  private def handle_ws_play_tts(connection, obj, session, thread)
    # Handle play TTS message
    # This is similar to auto_speech processing but for card playback

    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    # Stop any existing TTS thread first
    if defined?(@tts_thread) && @tts_thread && @tts_thread.alive?
      @tts_thread.kill
      @tts_thread = nil
    end

    thread&.join

    # Extract TTS parameters
    provider = obj["tts_provider"]
    if provider == "elevenlabs" || provider == "elevenlabs-flash" || provider == "elevenlabs-multilingual" || provider == "elevenlabs-v3"
      voice = obj["elevenlabs_tts_voice"]
    elsif provider == "gemini-flash" || provider == "gemini-pro"
      voice = obj["gemini_tts_voice"]
    elsif provider == "mistral"
      voice = obj["mistral_tts_voice"]
    elsif provider == "grok"
      voice = obj["grok_tts_voice"]
    else
      voice = obj["tts_voice"]
    end
    text = obj["text"]
    speed = obj["tts_speed"]
    response_format = "aac"
    language = obj["conversation_language"] || "auto"

    # Use common TTS playback method with manual_play: true (no byte limit for explicit Play button)
    start_tts_playback(
      text: text,
      provider: provider,
      voice: voice,
      speed: speed,
      response_format: response_format,
      language: language,
      manual_play: true,
      ws_session_id: ws_session_id
    )
  end

end
