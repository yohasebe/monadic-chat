require 'json'
require 'shellwords'

module MusicAdvisorTools
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

class MusicAdvisorOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  include MusicAdvisorTools
end

class MusicAdvisorClaude < MonadicApp
  include ClaudeHelper if defined?(ClaudeHelper)
  include MusicAdvisorTools
end
