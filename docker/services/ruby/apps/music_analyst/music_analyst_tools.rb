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
  # Fallback Gemini model for qualitative critique when the SSOT default is
  # unavailable. Must support audio input; gemini-3.5-flash does.
  CRITIQUE_MODEL_FALLBACK = "gemini-3.5-flash"

  # critique_audio is for real audio only; MIDI has no waveform to "listen" to.
  CRITIQUE_AUDIO_EXTS = %w[mp3 mpeg m4a mp4 wav ogg flac].freeze

  # OBJECTIVE lens: deterministic feature extraction via signal processing.
  def analyze_audio_features(file_path:, session: nil)
    filename = File.basename(file_path.to_s)
    ext = File.extname(filename).delete_prefix(".").downcase
    # Audio (not MIDI) feature extraction needs the optional Audio Analysis
    # package (librosa + madmom). If it isn't installed, fail with a clear,
    # actionable message instead of a cryptic analyzer crash. MIDI uses
    # pretty_midi and self-reports its own missing dependency, so it falls
    # through to the script.
    if CRITIQUE_AUDIO_EXTS.include?(ext) && !audio_analysis_package_enabled?
      return "❌ Objective audio analysis needs the optional Audio Analysis package " \
             "(librosa + madmom). Enable it under Actions → Install Options and rebuild " \
             "the Python container. The interpretive critique (critique_audio) works without it."
    end
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
    AudioAnalysisAgent.analyze(audio_path: abs_path, prompt: build_critique_prompt(focus), model: critique_model)
  rescue StandardError => e
    "❌ Audio critique failed: #{e.message}"
  end

  private

  # The optional "librosa + madmom" install option (Actions → Install Options)
  # is recorded as PYOPT_LIBROSA in the runtime config. Without it the Python
  # audio path can't run, so we gate on it to give an actionable message.
  def audio_analysis_package_enabled?
    defined?(CONFIG) && CONFIG.respond_to?(:[]) &&
      CONFIG["PYOPT_LIBROSA"].to_s.strip.downcase == "true"
  end

  # Resolve the audio-capable Gemini model from the SSOT (providerDefaults),
  # falling back to a known-good model — mirrors the agent model strategy in
  # CLAUDE.md (ModelSpec accessor + hardcoded fallback).
  def critique_model
    if defined?(Monadic::Utils::ModelSpec)
      Monadic::Utils::ModelSpec.default_audio_model("gemini") || CRITIQUE_MODEL_FALLBACK
    else
      CRITIQUE_MODEL_FALLBACK
    end
  rescue StandardError
    CRITIQUE_MODEL_FALLBACK
  end

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
      # Drop spurious brief No-Chord blips (monophonic solo lines make madmom
      # emit short "N.C." spans between real chords); keep N.C. spans >= 1s as
      # genuinely chord-less passages. `.to_f` is nil-safe — chord entries may
      # carry no duration. Then collapse consecutive duplicates.
      meaningful = chords.reject { |c| c["chord"] == "N.C." && c["duration"].to_f < 1.0 }
      seq = meaningful.map { |c| c["chord"] }.compact.chunk_while { |a, b| a == b }.map(&:first)
      if seq.any?
        suffix = seq.length > 24 ? " …" : ""
        lines << "- Chords: #{seq.first(24).join(' - ')}#{suffix}"
      end
    end

    sections = result["sections"]
    if sections.is_a?(Array) && sections.any?
      lines << "- Sections: #{sections.map { |s| s['label'] }.compact.join(', ')}"
    end

    # MIDI files additionally carry per-track instrument info.
    tracks = result["tracks"]
    if tracks.is_a?(Array) && tracks.any?
      names = tracks.map { |t| t["name"] || t["instrument"] }.compact
      lines << "- Tracks: #{names.join(', ')}" if names.any?
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
