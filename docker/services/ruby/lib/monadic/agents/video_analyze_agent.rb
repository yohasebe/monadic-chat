module VideoAnalyzeAgent
  def analyze_video(file:, fps: 1, query: nil)
    return "Error: file is required." if file.to_s.empty?

    split_command = <<~CMD
      bash -c 'extract_frames.py "#{file}" ./ --fps #{fps} --format png --json --audio'
    CMD

    split_res = send_command(command: split_command, container: "python")

    prompt = <<~TEXT
      The user tried to split the video into frames using a command and got the following response. If the process was successful, the user will get a JSON file containing the list of base64 images of the frames extracted from the video and an audio file. The two files will be separated by a semicolon. If it is not successful, the user will get an error message. Examine the command response and provide the result in the following JSON format:

      {
        "result": "success" | "error",
        "content": JSON_FILE;AUDIO_FILE | ERROR_MESSAGE
      }

      ### Command Response

      #{split_res}
    TEXT

    agent_res = command_output_agent(prompt, split_res)

    if agent_res["result"] == "success"
      json_file, audio_file = agent_res["content"].split(";")
    else
      return agent_res["content"]
    end

    query = query ? " \"#{query}\"" : ""

    model = settings["model"] || settings[:model]

    model = check_vision_capability(model) || "gpt-4.1"

    video_command = <<~CMD
      bash -c 'simple_video_query.rb "#{json_file}" #{query} "#{model}"'
    CMD

    description = send_command(command: video_command, container: "ruby")

    if audio_file
      # video description needs whisper-1, not gpt-4o-mini-tts
      stt_model = "whisper-1" 
      
      audio_command = <<~CMD
        bash -c 'simple_stt_query.rb "#{audio_file}" "." "srt" "" "#{stt_model}"'
      CMD
      audio_description = send_command(command: audio_command, container: "ruby")

      description += "\n\n---\n\n"
      description += "Audio Transcript:\n#{audio_description}"
    end
    description
  end
end
