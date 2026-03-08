# frozen_string_literal: true

# Speech-to-text (STT) audio processing for WebSocket connections.
# Handles audio transcription requests, confidence calculation,
# and result delivery.

module WebSocketHelper
  # Handle AUDIO message
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param obj [Hash] Parsed message object
  def handle_audio_message(connection, obj)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    if obj["content"].nil?
      error_message = { "type" => "error", "content" => "voice_input_empty" }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(error_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(error_message)
      end
      return
    end

    # Decode audio content
    blob = Base64.decode64(obj["content"])

    # Get STT model from Web UI (priority) or use default
    model = obj["stt_model"] || "gpt-4o-mini-transcribe-2025-12-15"
    format = obj["format"] || "webm"

    # Store stt_model in session for use by other components (e.g., Video Describer)
    session[:parameters] ||= {}
    session[:parameters]["stt_model"] = model

    # Process the transcription
    process_transcription(connection, blob, format, obj["lang_code"], model, ws_session_id)
  end

  # Process audio transcription
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param blob [String] The decoded audio data
  # @param format [String] The audio format
  # @param lang_code [String] The language code
  # @param model [String] The model to use
  # @param ws_session_id [String] WebSocket session ID for targeted broadcasting
  def process_transcription(connection, blob, format, lang_code, model, ws_session_id = nil)
    begin
      # Request transcription
      res = stt_api_request(blob, format, lang_code, model)

      if res["text"] && res["text"] == ""
        empty_error = { "type" => "error", "content" => "text_input_empty" }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(empty_error, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(empty_error)
        end
      elsif res["type"] && res["type"] == "error"
        # Include format information in error message for debugging
        error_content = "#{res["content"]} (using format: #{format}, model: #{model})"
        api_error = { "type" => "error", "content" => error_content }.to_json
        if ws_session_id
          WebSocketHelper.send_to_session(api_error, ws_session_id)
        else
          WebSocketHelper.broadcast_to_all(api_error)
        end
      else
        send_transcription_result(connection, res, model)
      end
    rescue StandardError => e
      # Log the error but don't crash the application
      log_error("Error processing transcription", e)

      # Send a generic error message to the client
      rescue_error = {
        "type" => "error",
        "content" => "An error occurred while processing your audio"
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(rescue_error, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(rescue_error)
      end
    end
  end

  # Calculate confidence and send transcription result
  # @param connection [Async::WebSocket::Connection] WebSocket connection
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  def send_transcription_result(connection, res, model)
    # Get session ID for targeted broadcasting
    ws_session_id = Thread.current[:websocket_session_id]

    begin
      logprob = calculate_logprob(res, model)

      stt_message = {
        "type" => "stt",
        "content" => res["text"],
        "logprob" => logprob
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(stt_message, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(stt_message)
      end
    rescue StandardError => e
      # Handle errors in logprob calculation
      stt_message_no_logprob = {
        "type" => "stt",
        "content" => res["text"]
      }.to_json
      if ws_session_id
        WebSocketHelper.send_to_session(stt_message_no_logprob, ws_session_id)
      else
        WebSocketHelper.broadcast_to_all(stt_message_no_logprob)
      end
    end
  end

  # Calculate log probability for transcription confidence
  # @param res [Hash] The transcription result
  # @param model [String] The model used
  # @return [Float, nil] The calculated log probability or nil on error
  def calculate_logprob(res, model)
    # Gemini models do not support logprobs for STT
    return nil if model.start_with?("gemini-")

    # ElevenLabs Scribe models - use logprobs array if available
    if model.start_with?("scribe")
      return nil unless res["logprobs"].is_a?(Array) && !res["logprobs"].empty?
      avg_logprobs = res["logprobs"].map { |s| s["logprob"].to_f }
      return Math.exp(avg_logprobs.sum / avg_logprobs.size).round(2)
    end

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
end
