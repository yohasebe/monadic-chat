# frozen_string_literal: true

require "json"
require "shellwords"
require_relative "../../lib/monadic/utils/environment"
require_relative "../../lib/monadic/agents/audio_analysis_agent"

# Tools for the Music Analyst app: two complementary lenses on an uploaded
# audio file.
#   - analyze_audio_features: OBJECTIVE / measured (DSP via music_analyzer.py)
#   - critique_audio:         INTERPRETIVE / qualitative (Gemini audio understanding)
#
# The DSP feature extraction is provider-independent (Python). The qualitative
# critique is Gemini-specific (see AudioAnalysisAgent), so this module is only
# included into the Gemini variant — Provider Independence is preserved.
module MusicAnalystTools
  # Gemini model for qualitative critique. Must support audio input;
  # gemini-3.5-flash does and is cost-effective for this task.
  CRITIQUE_MODEL = "gemini-3.5-flash"

  # critique_audio is for real audio only; MIDI has no waveform to "listen" to.
  CRITIQUE_AUDIO_EXTS = %w[mp3 mpeg m4a mp4 wav ogg flac].freeze

  # OBJECTIVE lens: deterministic feature extraction via signal processing.
  def analyze_audio_features(file_path:, session: nil)
    filename = File.basename(file_path.to_s)
    # send_command targets the python container, where the shared volume is
    # always mounted at /monadic/data regardless of host/container mode.
    container_path = "/monadic/data/#{filename}"
    params = JSON.generate({ "file_path" => container_path })
    cmd = "python3 /monadic/scripts/music/music_analyzer.py analyze --params #{Shellwords.escape(params)}"
    stdout = send_command(command: cmd, container: "python")
    result = extract_json(stdout)

    if result.is_a?(Hash) && result["success"]
      format_features(result)
    else
      msg = result.is_a?(Hash) ? result["error"] : "Unknown error"
      "❌ Audio feature analysis failed: #{msg}"
    end
  rescue StandardError => e
    "❌ Audio feature analysis failed: #{e.message}"
  end

  # INTERPRETIVE lens: Gemini listens and critiques the music/performance.
  def critique_audio(file_path:, focus: nil, session: nil)
    filename = File.basename(file_path.to_s)
    ext = File.extname(filename).delete_prefix(".").downcase
    unless CRITIQUE_AUDIO_EXTS.include?(ext)
      return "❌ critique_audio supports audio only (#{CRITIQUE_AUDIO_EXTS.join(', ')}). " \
             "For MIDI, use analyze_audio_features."
    end

    # The Ruby process reads the file directly, so resolve to the mode-correct
    # shared-volume path (container: /monadic/data, host: ~/monadic/data).
    abs_path = File.join(Monadic::Utils::Environment.data_path, filename)
    AudioAnalysisAgent.analyze(audio_path: abs_path, prompt: build_critique_prompt(focus), model: CRITIQUE_MODEL)
  rescue StandardError => e
    "❌ Audio critique failed: #{e.message}"
  end

  private

  def build_critique_prompt(focus)
    prompt = <<~PROMPT
      You are an expert music critic and performance analyst. Listen to the audio and write an interpretive, qualitative critique of the MUSIC and PERFORMANCE.

      Cover, as applicable:
      - Overall character, mood, and emotional arc
      - Genre / style and the instrumentation you hear
      - Performance qualities: expression, dynamics, phrasing, articulation, timing/groove, energy, and ensemble interplay
      - Notable strengths and any weaknesses, with specific, time-anchored observations where possible
      - A concise overall evaluation

      Honesty about limits (mention these only if relevant or asked):
      - Do NOT assess audio fidelity, mix/mastering, or stereo imaging — the audio is reduced to mono at limited bandwidth and is unsuitable for sound-quality judgements.
      - Do NOT state exact BPM, key, or pitch in Hz/cents as measured facts; those come from the objective feature-analysis tool. You may describe tempo and tonality impressionistically (e.g. "a relaxed, moderate tempo").

      Write clear prose, not a filled-in form. Respond in the user's language.
    PROMPT
    prompt += "\nAdditional focus requested by the user: #{focus}\n" if focus && !focus.to_s.strip.empty?
    prompt
  end

  # Compact objective summary using the music_analyzer.py JSON schema
  # (tempo/key/time_signature are nested objects; chords/sections are arrays).
  def format_features(result)
    lines = ["**Objective features** (measured via signal processing):"]

    if (dur = result["duration_seconds"])
      lines << "- Duration: #{(dur / 60).to_i}:#{format('%02d', (dur % 60).to_i)}"
    end
    if (bpm = result.dig("tempo", "bpm"))
      lines << "- Tempo: #{bpm.round(1)} BPM"
    end
    if (key = result.dig("key", "key"))
      mode = result.dig("key", "mode")
      lines << "- Key: #{key}#{mode ? " #{mode}" : ''}"
    end
    if (bpb = result.dig("time_signature", "beats_per_bar"))
      nv = result.dig("time_signature", "note_value") || 4
      lines << "- Time signature: #{bpb}/#{nv}"
    end

    chords = result["chords"]
    if chords.is_a?(Array) && chords.any?
      seq = chords.map { |c| c["chord"] }.compact.chunk_while { |a, b| a == b }.map(&:first)
      suffix = seq.length > 24 ? " …" : ""
      lines << "- Chords: #{seq.first(24).join(' - ')}#{suffix}"
    end

    sections = result["sections"]
    if sections.is_a?(Array) && sections.any?
      lines << "- Sections: #{sections.map { |s| s['label'] }.compact.join(', ')}"
    end

    lines << "- Summary: #{result['description']}" if result["description"]
    lines.join("\n")
  end

  # The Python analyzer prints JSON, sometimes with a wrapping success message;
  # extract the outermost JSON object defensively.
  def extract_json(output)
    return output if output.is_a?(Hash)
    text = output.to_s
    start = text.index("{")
    finish = text.rindex("}")
    return { "success" => false, "error" => "No JSON in analyzer output" } unless start && finish && finish > start
    JSON.parse(text[start..finish])
  rescue JSON::ParserError => e
    { "success" => false, "error" => "Parse error: #{e.message}" }
  end
end

class MusicAnalystGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MusicAnalystTools
end
