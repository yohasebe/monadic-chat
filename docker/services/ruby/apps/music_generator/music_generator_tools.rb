# frozen_string_literal: true

require 'json'
require 'securerandom'

# ElevenLabs Music for the Music Generator.
#
# The app runs on Gemini and generates with Lyria. ElevenLabs is a second
# service the user can ask for by name, so three rules hold (the user's
# decision, 2026-10-05):
#   a. it is used only when the user explicitly asks for ElevenLabs;
#   b. it is never a fallback when Lyria fails;
#   c. every result says which service made it (the `service` field).
# The tool is offered only when ELEVENLABS_API_KEY is configured: the Gemini
# helper drops it from the request otherwise (Monadic::Utils::ToolKeyRequirements),
# and the method below refuses without a key as well.
module MusicGeneratorTools
  ELEVENLABS_MUSIC_ENDPOINT = "https://api.elevenlabs.io/v1/music"
  ELEVENLABS_MUSIC_SERVICE = "ElevenLabs Music"
  # The API accepts 3 seconds to 10 minutes.
  ELEVENLABS_MUSIC_MIN_MS = 3_000
  ELEVENLABS_MUSIC_MAX_MS = 600_000
  # 128 kbps is available on every paid plan; higher bitrates are plan-gated.
  ELEVENLABS_MUSIC_OUTPUT_FORMAT = "mp3_44100_128"

  def generate_music_with_elevenlabs(prompt:, length_seconds: nil, instrumental: nil, session: nil)
    api_key = CONFIG["ELEVENLABS_API_KEY"].to_s.strip
    if api_key.empty?
      return { success: false, service: ELEVENLABS_MUSIC_SERVICE,
               error: "ELEVENLABS_API_KEY is not configured" }.to_json
    end

    model_id = elevenlabs_music_model
    body = { prompt: prompt.to_s, model_id: model_id }
    length_ms = elevenlabs_music_length_ms(length_seconds)
    body[:music_length_ms] = length_ms if length_ms
    body[:force_instrumental] = true if [true, "true", "yes", 1].include?(instrumental)

    response = nil
    Monadic::Utils::ProgressBroadcaster.with_progress(
      source: "MusicGeneratorGemini",
      label: "Generating music with ElevenLabs (#{model_id})"
    ) do
      response = Monadic::Utils::HttpClient.generation
                   .headers("xi-api-key" => api_key, "Accept" => "audio/mpeg")
                   .post("#{ELEVENLABS_MUSIC_ENDPOINT}?output_format=#{ELEVENLABS_MUSIC_OUTPUT_FORMAT}", json: body)
    end

    unless response.status.success?
      return { success: false, service: ELEVENLABS_MUSIC_SERVICE,
               error: elevenlabs_music_error(response) }.to_json
    end

    mime = response.content_type&.mime_type.to_s
    mime = "audio/mpeg" unless mime.start_with?("audio/")
    ext = mime.include?("wav") ? "wav" : "mp3"
    filename = "elevenlabs_music_#{Time.now.to_i}_#{SecureRandom.hex(3)}.#{ext}"
    filepath = File.join(Monadic::Utils::Environment.shared_volume, filename)
    File.binwrite(filepath, response.body.to_s)

    { success: true, service: ELEVENLABS_MUSIC_SERVICE, filename: filename, mime_type: mime,
      model: model_id, prompt: prompt }.to_json
  rescue StandardError => e
    { success: false, service: ELEVENLABS_MUSIC_SERVICE,
      error: Monadic::Utils::ErrorFormatter.tool_error(
        provider: "ElevenLabs",
        tool_name: "generate_music_with_elevenlabs",
        message: e.message
      ) }.to_json
  end

  private

  def elevenlabs_music_model
    models = Monadic::Utils::ModelSpec.get_provider_models("elevenlabs", "music")
    Array(models).first || "music_v2_5"
  rescue StandardError
    "music_v2_5"
  end

  def elevenlabs_music_length_ms(length_seconds)
    return nil if length_seconds.nil? || length_seconds.to_s.strip.empty?

    seconds = Float(length_seconds)
    return nil unless seconds.positive?

    (seconds * 1000).round.clamp(ELEVENLABS_MUSIC_MIN_MS, ELEVENLABS_MUSIC_MAX_MS)
  rescue ArgumentError, TypeError
    nil
  end

  # The API's own message, without its request details: errors come back as
  # {"detail": {"status": ..., "message": ...}} or {"detail": "..."}.
  def elevenlabs_music_error(response)
    data = JSON.parse(response.body.to_s) rescue {}
    detail = data["detail"]
    message = detail.is_a?(Hash) ? (detail["message"] || detail["status"]) : detail
    message = message.to_s.strip
    message = "ElevenLabs returned HTTP #{response.status.code}" if message.empty?
    message[0, 400]
  end
end
