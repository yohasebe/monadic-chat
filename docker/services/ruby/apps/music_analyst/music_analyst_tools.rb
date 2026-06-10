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
      - A *tentative* sense of genre / style (hedged, never a firm label — see below) and the instruments you can clearly identify by ear
      - Performance qualities: expression, dynamics, phrasing, articulation, timing/groove, energy, and ensemble interplay
      - Notable strengths and any weaknesses
      - A concise overall evaluation

      Honesty about limits (mention these only if relevant or asked):
      - Do NOT assess audio fidelity, mix/mastering, stereo imaging, or the quality of the production — the audio reaches you as roughly 16 kHz mono and is unsuitable for ANY sound-quality or production judgement. Comment on the playing, never on the recording.
      - Do NOT state exact BPM, key, or pitch in Hz/cents as measured facts; those come from the objective feature-analysis tool. You may describe tempo and tonality impressionistically (e.g. "a relaxed, moderate tempo").
      - Describe only what you can actually hear in this recording. Do NOT invent details — do not name techniques or events that are not actually present. When an observation is uncertain, hedge it ("seems to", "possibly") or leave it out rather than stating it with confidence. You may point to specific passages or moments, but only when you are confident they are accurate.

      Instrumentation — be especially careful, because confident mistakes here are the most common and the most damaging:
      - Name an instrument ONLY when you can clearly and directly hear it in THIS recording. Do NOT infer instruments from the genre, the style, or what a "typical" or "standard" ensemble for this kind of music would include. Convention is not evidence.
      - When you are unsure what an instrument is, describe the SOUND instead of committing to a name — its register, timbre, and role (e.g. "a low, sustained bass-register part", "a bright plucked-string lead", "drums/percussion") — or simply leave it out. Never upgrade an uncertain impression into a definite instrument name.
      - Prefer under-counting to over-counting: do not assemble a fuller band than you can actually hear. Listing only the parts you are sure of is correct; if useful, you may add that other parts could be present but cannot be confirmed by ear. Missing a faint part is far better than inventing one that is not there.
      - The same caution applies to effects and signal processing (wah, envelope filter, delay, chorus, etc.): do not assert their use. Textures produced by playing technique alone — fluid legato runs, bends, vibrato, picking dynamics — can closely resemble a filter sweep or other processing. When unsure, describe the texture itself instead of naming an effect, or hedge the attribution explicitly.

      Candor and balance — a critique that only praises is incomplete:
      - Always include BOTH notable strengths AND concrete weaknesses, each grounded in something you actually heard (a specific passage, tendency, or moment). If you genuinely find no weakness worth noting, say so explicitly — do not pad the critique with extra praise instead.
      - When you notice instability — timing that rushes or drags, pitch that drifts, uneven articulation, blurred runs — point it out plainly and concretely. A real flaw named precisely is more valuable to the performer than tact; never soften a real observation into a compliment.

      Genre, style, and other interpretive labels — calibrate your confidence:
      - Genre/style is an INFERENCE, not something you can hear directly. Do NOT commit to a single definitive label. Offer it tentatively — hedge it ("feels like", "leans toward", "has the energy of") or give two plausible candidates — never state one genre as a fact.
      - Impressionistic descriptions of the feel are welcome and encouraged ("a bluesy, hard-driving feel", "a relaxed, swung groove"); taxonomic pronouncements ("this is funk-rock") are not. The same caution applies to era, influences, and the performer's intent — these are guesses, so mark them as guesses.
      - Keep what you HEAR separate from what you INFER. Be specific and confident about the audible performance — articulation, dynamics, phrasing, timing/groove, energy, ensemble interplay; those you can defend. Be explicitly tentative about anything derived from it (genre, era, influences). Vivid, concrete description of the playing is the goal — calibrate the labels, do not flatten the prose.

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
