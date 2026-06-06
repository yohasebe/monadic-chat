# frozen_string_literal: true

require "base64"
require "http"
require "json"
require "tempfile"
require_relative "../utils/environment"

# AudioAnalysisAgent: Gemini-based *qualitative* analysis of audio.
#
# Distinct from AudioTranscriptionAgent (speech -> text): this sends audio to
# Gemini's multimodal generateContent with an analytical prompt to obtain an
# interpretive critique of the music/performance (mood, dynamics, phrasing,
# genre, overall impression).
#
# Gemini-specific by design: qualitative audio understanding is Gemini's
# capability here. Provider Independence is preserved because this agent is
# only wired into the Gemini variant of Music Analyst.
module AudioAnalysisAgent
  ANALYSIS_CONNECT_TIMEOUT = 10
  ANALYSIS_READ_TIMEOUT = 240   # music files can be long
  ANALYSIS_WRITE_TIMEOUT = 60
  ANALYSIS_MAX_RETRIES = 1

  # Gemini downsamples audio to 16 kHz mono regardless of input, so files above
  # this size are pre-compressed to mp3 16 kHz mono — shrinking the inline_data
  # payload with no loss of information Gemini would have used anyway.
  COMPRESS_THRESHOLD_BYTES = 6 * 1024 * 1024

  AUDIO_MIME_TYPES = {
    "mp3"  => "audio/mpeg", "mpeg" => "audio/mpeg",
    "m4a"  => "audio/mp4",  "mp4"  => "audio/mp4",
    "wav"  => "audio/wav",  "ogg"  => "audio/ogg",
    "flac" => "audio/flac"
  }.freeze

  module_function

  # @param audio_path [String] absolute path to an audio file (Ruby-process local)
  # @param prompt [String] analytical instruction
  # @param model [String] Gemini model id (must support audio input)
  # @return [String] Gemini's qualitative analysis text, or "ERROR: ..."
  def analyze(audio_path:, prompt:, model:)
    api_key = defined?(CONFIG) ? CONFIG["GEMINI_API_KEY"] : ENV.fetch("GEMINI_API_KEY", nil)
    return "ERROR: GEMINI_API_KEY not configured" if api_key.nil? || api_key.to_s.empty?
    return "ERROR: Audio file not found: #{audio_path}" unless File.exist?(audio_path)

    send_path, mime_type, cleanup = prepare_audio(audio_path)
    begin
      base64_data = Base64.strict_encode64(File.binread(send_path))
      uri = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent?key=#{api_key}"
      body = {
        contents: [{
          parts: [
            { inline_data: { mime_type: mime_type, data: base64_data } },
            { text: prompt }
          ]
        }]
      }
      post_and_parse(uri, body)
    ensure
      cleanup&.call
    end
  rescue StandardError => e
    "ERROR: Audio analysis failed: #{e.message}"
  end

  # Compress large files to mp3 16 kHz mono via ffmpeg (mirrors the proven
  # array-form invocation in stt_utils). Returns [path, mime, cleanup_or_nil];
  # falls back to the original file if ffmpeg is unavailable or fails.
  def prepare_audio(audio_path)
    ext = File.extname(audio_path).delete_prefix(".").downcase
    mime = AUDIO_MIME_TYPES[ext] || "audio/mpeg"
    return [audio_path, mime, nil] if File.size(audio_path) < COMPRESS_THRESHOLD_BYTES

    tmp = Tempfile.new(["music_analyst", ".mp3"])
    tmp.close
    ok = system("ffmpeg", "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", "-b:a", "64k", tmp.path,
                %i[out err] => File::NULL)
    if ok && File.size?(tmp.path)
      [tmp.path, "audio/mpeg", -> { tmp.unlink rescue nil }]
    else
      tmp.unlink rescue nil
      [audio_path, mime, nil]
    end
  end

  def post_and_parse(uri, body)
    retries = 0
    begin
      res = HTTP.headers("Content-Type" => "application/json")
               .timeout(connect: ANALYSIS_CONNECT_TIMEOUT, write: ANALYSIS_WRITE_TIMEOUT, read: ANALYSIS_READ_TIMEOUT)
               .post(uri, json: body)
    rescue HTTP::Error, HTTP::TimeoutError => e
      if retries < ANALYSIS_MAX_RETRIES
        retries += 1
        sleep 1
        retry
      end
      return "ERROR: Gemini request failed: #{e.message}"
    end

    unless res.status.success?
      error = JSON.parse(res.body.to_s) rescue {}
      return "ERROR: Gemini API error (#{res.status}): #{error.dig('error', 'message') || res.body.to_s}"
    end

    parsed = JSON.parse(res.body.to_s)
    parsed.dig("candidates", 0, "content", "parts", 0, "text") || "ERROR: Empty response from Gemini"
  end
end
