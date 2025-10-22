module VideoAnalyzeAgent
  def analyze_video(file:, fps: 1, query: nil)
    return "Error: file is required." if file.to_s.empty?

    split_command = <<~CMD
      bash -c 'extract_frames.py "#{file}" ./ --fps #{fps} --format png --json --audio'
    CMD

    split_res = send_command(command: split_command, container: "python")

    # Debug output
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "DEBUG: extract_frames output: #{split_res.inspect}"
    end

    # Parse the output directly instead of using AI
    json_file = nil
    audio_file = nil
    
    # Look for patterns in the output
    if split_res =~ /Base64-encoded frames saved to (.+\.json)/
      json_file = $1.strip
    end
    
    if split_res =~ /Audio extracted to (.+\.mp3)/
      audio_file = $1.strip
    end
    
    # Check if extraction was successful
    if json_file.nil? || json_file.empty?
      return "Error: Failed to extract frames from video. Output: #{split_res}"
    end
    
    # Debug output
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "DEBUG: Parsed json_file: #{json_file.inspect}, audio_file: #{audio_file.inspect}"
    end

    query = query ? " \"#{query}\"" : ""

    model = settings["model"] || settings[:model]

    model = check_vision_capability(model) || "gpt-4.1"

    video_command = <<~CMD
      bash -c 'video_query.rb "#{json_file}" #{query} "#{model}"'
    CMD

    # Debug output
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "DEBUG: Executing video_command: #{video_command.inspect}"
    end

    description = send_command(command: video_command, container: "ruby")
    
    # Debug output
    if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] && !defined?(RSpec)
      puts "DEBUG: video_query result: #{description.inspect}"
    end
    
    # Check if there was an error
    if description.to_s.start_with?("ERROR:", "Error:")
      return "Video analysis failed: #{description}"
    end

    if audio_file
      # Priority for STT model selection:
      # 1. Web UI selection (user's explicit choice from session)
      # 2. MDSL default (app developer's recommendation via agents block)
      # 3. System default (fallback)
      stt_model = session[:parameters]&.[]("stt_model") ||      # Web UI selection
                  settings.dig(:agents, :speech_to_text) ||     # MDSL default
                  "gpt-4o-mini-transcribe"                      # System default

      if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"]
        puts "[VideoAnalyzer] Using STT model: #{stt_model}"
        puts "  - Web UI selection: #{session[:parameters]&.[]('stt_model') || 'none'}"
        puts "  - MDSL default: #{settings.dig(:agents, :speech_to_text) || 'none'}"
      end

      audio_command = <<~CMD
        bash -c 'stt_query.rb "#{audio_file}" "." "srt" "" "#{stt_model}"'
      CMD
      audio_description = send_command(command: audio_command, container: "ruby")
      
      # Check if there was an error with audio processing
      if audio_description.to_s.start_with?("ERROR:", "Error:", "An error occurred:")
        audio_description = "Audio transcription failed: #{audio_description}"
      end

      description += "\n\n---\n\n"
      description += "Audio Transcript:\n#{audio_description}"
    end
    description
  end
end
