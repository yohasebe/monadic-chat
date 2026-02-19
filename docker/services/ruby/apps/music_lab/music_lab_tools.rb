require 'json'
require 'shellwords'

module MusicLabTools
  def play_chord(chord_name:, voicing: nil, instrument: nil, octave: nil, session: nil)
    params = { "chord_name" => chord_name }
    params["voicing"] = voicing if voicing
    params["instrument"] = instrument if instrument
    params["octave"] = octave if octave

    run_music_action("chord", params, session)
  end

  def play_scale(scale_name:, root:, octave: nil, direction: nil, instrument: nil, session: nil)
    params = { "scale_name" => scale_name, "root" => root }
    params["octave"] = octave if octave
    params["direction"] = direction if direction
    params["instrument"] = instrument if instrument

    run_music_action("scale", params, session)
  end

  def play_interval(root:, interval:, octave: nil, instrument: nil, session: nil)
    params = { "root" => root, "interval" => interval }
    params["octave"] = octave if octave
    params["instrument"] = instrument if instrument

    run_music_action("interval", params, session)
  end

  def play_progression(chords:, tempo: nil, instrument: nil, bars_per_chord: nil, octave: nil, session: nil)
    params = { "chords" => chords }
    params["tempo"] = tempo if tempo
    params["instrument"] = instrument if instrument
    params["bars_per_chord"] = bars_per_chord if bars_per_chord
    params["octave"] = octave if octave

    run_music_action("progression", params, session)
  end

  def generate_backing_track(chords:, tempo: nil, style: nil, bars: nil, instruments: nil, octave: nil, melody: nil, melody_instrument: nil, melody_style: nil, melody_seed: nil, session: nil)
    params = { "chords" => chords }
    params["tempo"] = tempo if tempo
    params["style"] = style if style
    params["bars"] = bars if bars
    params["instruments"] = instruments if instruments
    params["octave"] = octave if octave
    params["melody"] = melody if melody
    params["melody_instrument"] = melody_instrument if melody_instrument
    params["melody_style"] = melody_style if melody_style
    params["melody_seed"] = melody_seed if melody_seed

    run_music_action("backing", params, session)
  end

  def analyze_audio_file(file_path:, session: nil)
    # Normalize path to /monadic/data/ (the shared folder inside the container)
    container_path = if file_path.start_with?("/monadic/data")
                       file_path
                     else
                       "/monadic/data/#{file_path}"
                     end

    params = { "file_path" => container_path }
    json_params = JSON.generate(params)
    cmd = "python3 /monadic/scripts/music/music_analyzer.py analyze --params #{Shellwords.escape(json_params)}"
    stdout = send_command(command: cmd, container: "python")
    result = parse_music_result(stdout)

    if result.is_a?(Hash) && result["success"]
      format_analysis_result(result)
    else
      error_msg = result.is_a?(Hash) ? result["error"] : "Unknown error"
      "Error: #{error_msg}"
    end
  rescue => e
    "Error: Audio analysis failed: #{e.message}"
  end

  private

  def run_music_action(action, params, session)
    cmd = build_music_command(action, params)
    stdout = send_command(command: cmd, container: "python")
    result = parse_music_result(stdout)

    if result.is_a?(Hash) && result["success"]
      # Store ABC notation as HTML fragment for post-response injection via session.
      # The helper's generic tool_html_fragments mechanism will append this after the model's text.
      # ABCJS in the browser handles rendering and MIDI playback via WebAudio synthesis.
      if result["abc"] && session
        abc_html = "<div class=\"abc-code\"><pre>#{result["abc"]}</pre></div>"
        session[:tool_html_fragments] ||= []
        session[:tool_html_fragments] << abc_html
      end

      # Return text description for the model (no ABC — it's injected separately)
      text = "#{result['description']}\n"
      text += "Notes: #{result['notes'].join(', ')}\n" if result["notes"]&.any?
      text
    else
      error_msg = result.is_a?(Hash) ? result["error"] : "Unknown error"
      "Error: #{error_msg}"
    end
  rescue => e
    "Error: Music generation failed: #{e.message}"
  end

  def format_analysis_result(result)
    file_name = result["file_name"] || "unknown"
    file_type = result["file_type"] || "audio"
    duration = result["duration_seconds"] || 0
    dur_min = (duration / 60).to_i
    dur_sec = (duration % 60).to_i

    tempo = result.dig("tempo", "bpm") || 0
    key_name = result.dig("key", "key") || "Unknown"
    key_mode = result.dig("key", "mode") || "unknown"
    beats_per_bar = result.dig("time_signature", "beats_per_bar") || 4
    note_value = result.dig("time_signature", "note_value") || 4

    lines = []
    heading = file_type == "midi" ? "MIDI Analysis" : "Audio Analysis"
    lines << "## #{heading}: #{file_name}"
    lines << "- Duration: #{dur_min}:#{format('%02d', dur_sec)}"
    lines << "- Tempo: #{tempo.round(1)} BPM"

    if file_type == "midi"
      key_source = result.dig("key", "source") || "unknown"
      lines << "- Key: #{key_name} #{key_mode} (source: #{key_source})"
    else
      key_conf = result.dig("key", "confidence") || 0
      lines << "- Key: #{key_name} #{key_mode} (confidence: #{(key_conf * 100).round}%)"
    end

    lines << "- Time Signature: #{beats_per_bar}/#{note_value}"

    if result["truncated"]
      orig = result["original_duration_seconds"] || 0
      lines << "- Note: Only first 5 minutes analyzed (full duration: #{(orig / 60).round(1)} min)"
    end

    # Tracks (MIDI only)
    tracks = result["tracks"] || []
    if tracks.any?
      lines << ""
      lines << "## Tracks:"
      tracks.each_with_index do |t, i|
        name = t["name"] || t["instrument"] || "Unknown"
        if t["is_drum"]
          lines << "#{i + 1}. #{name} (Drums) - #{t['note_count']} hits"
        else
          instrument = t["instrument"] || "Unknown"
          pitch_range = t["pitch_range"].to_s.empty? ? "" : ", #{t['pitch_range']}"
          lines << "#{i + 1}. #{name} (#{instrument}) - #{t['note_count']} notes#{pitch_range}"
        end
      end
    end

    chords = result["chords"] || []
    if chords.any?
      chord_method = result["chord_method"] || (file_type == "midi" ? "piano_roll" : "unknown")
      lines << ""
      lines << "## Chord Progression (method: #{chord_method}):"
      lines << ""

      # Build bar-aligned chord chart
      bar_chords = quantize_chords_to_bars(chords, tempo, beats_per_bar)
      if bar_chords.any?
        bar_chords.each_slice(4) do |row|
          cells = row.map { |bc| bc.center(12) }
          lines << "| #{cells.join(' | ')} |"
        end
        lines << ""
        lines << "_#{bar_chords.length} bars, #{bar_chords.uniq.length} unique chords_"
      end
    end

    sections = result["sections"] || []
    if sections.any?
      lines << ""
      lines << "## Sections:"
      sections.each do |s|
        s_start = s["start"].to_f
        s_end = s["end"].to_f
        lines << "#{s['label'].capitalize}: #{format_time(s_start)} - #{format_time(s_end)}"
      end
    end

    lines << ""
    lines << "## Summary"
    lines << result["description"] if result["description"]

    lines.join("\n")
  end

  def format_time(seconds)
    min = (seconds / 60).to_i
    sec = (seconds % 60).to_i
    "#{min}:#{format('%02d', sec)}"
  end

  def quantize_chords_to_bars(chords, tempo, beats_per_bar)
    return [] if chords.empty? || tempo.to_f <= 0 || beats_per_bar.to_f <= 0

    bar_duration = (beats_per_bar.to_f / tempo.to_f) * 60.0
    last_chord = chords.last
    total_duration = last_chord["time"].to_f + (last_chord["duration"]&.to_f || 2.0)
    total_bars = (total_duration / bar_duration).ceil
    total_bars = [total_bars, 200].min

    bars = Array.new(total_bars, nil)
    chords.each do |c|
      bar_index = (c["time"].to_f / bar_duration).floor
      next if bar_index >= total_bars
      bars[bar_index] ||= c["chord"]
    end

    # Fill nil bars with the preceding chord
    bars.each_with_index do |b, i|
      bars[i] = bars[i - 1] if b.nil? && i > 0
    end
    bars[0] ||= chords.first["chord"]
    bars.compact
  end

  def build_music_command(action, params)
    json_params = JSON.generate(params)
    "python3 /monadic/scripts/music/music_generator.py #{Shellwords.escape(action)} --params #{Shellwords.escape(json_params)}"
  end

  def parse_music_result(output)
    return { "success" => false, "error" => "No output from music generator" } if output.nil? || output.strip.empty?

    # send_command may prepend success messages; extract the JSON portion
    json_str = output.to_s.strip
    # Find the first '{' to handle any prefix text
    json_start = json_str.index('{')
    if json_start
      json_str = json_str[json_start..]
      # Find matching closing brace
      depth = 0
      json_str.each_char.with_index do |c, i|
        depth += 1 if c == '{'
        depth -= 1 if c == '}'
        if depth == 0
          json_str = json_str[0..i]
          break
        end
      end
    end

    JSON.parse(json_str)
  rescue JSON::ParserError => e
    { "success" => false, "error" => "Failed to parse music generator output: #{e.message}", "raw" => output.to_s[0..200] }
  end
end

class MusicLabOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MusicLabTools
end

class MusicLabClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MusicLabTools
end

class MusicLabGemini < MonadicApp
  include GeminiHelper if defined?(GeminiHelper)
  include MusicLabTools
end

class MusicLabGrok < MonadicApp
  include GrokHelper if defined?(GrokHelper)
  include MusicLabTools
end
