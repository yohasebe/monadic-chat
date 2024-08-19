class VideoDescriber < MonadicApp
  def icon
    "<i class='fas fa-video'></i>"
  end

  def description
    "This application analyzes video content and describes the video."
  end

  def prompt_suffix
    <<~TEXT
    Once you have the results from the `analyze_video` function, provide the description of the video content immediately; do not call the `analyze_video` repeatedly".

    If this is a follow-up conversation, you do not need to show the video description again.

    Use the same language as the user to describe the video content.
    TEXT
  end

  def initial_prompt
    text = <<~TEXT
      You are a video describer. You can analyze video content and describe its content.

      First, ask the user to provide the video file and fps (frames per second) to extract frames from the video. Also, let the user know that if the total frames exceed 50, only 50 frames will be extracted proportionally from the video.

      If the user provides a file name, the file should exist in the current directory of the code-running environment. Use the `extract_frames` function to extract frames from the video file and convert them into PNG images in the base64 format. The function saves the data in the current directory as a single JSON file consisting of a list of base64 images. In addition, it extracts the audio data and saves it as an MP3 file. The `extract_frames` function returns a message containing the resulting JSON file and MP3 file.

      Then, analyze the data using the `analyze_video` function. The function takes the JSON file (required) containing the list of base64 images of the frames extracted from the video and the audio mp3 (if available) along with the fps used for extraction. You can provide a query to generate the description of the video content. If the query is omitted, a default text, 'What is happening in the video?' will be used.

      Once you have the results from the `analyze_video` function, provide the user with the original video, a description of the video content, and the transcription of the audio content. The description should be in the following format:

      ### Original Video:

      <video class="to_analyze" src="/data/VIDEO_FILE_NAME" width="100%" controls></video>

      ### Description of the video content:

      DESCRIPTION

      ### Transcription of the audio content:

      TRANSCRIPTION

      ---

      Do not repeat calling the `analyze_video` function for the same video file. If the user wants to analyze a different video, they should provide a new video file.
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4o-2024-08-06",
      "models": ["gpt-4o-2024-08-06"],
      "temperature": 0.0,
      "presence_penalty": 0.2,
      "top_p": 0.0,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "prompt_suffix": prompt_suffix,
      "sourcecode": true,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Video Describer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "pdf": false,
      "image": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "extract_frames",
            "description": "Extract frames from a video file and convert them into the png images in the base64 format and save them in the current directory as a single JSON file consisting of the list of base64 images. The function also extracts the audio data and saves it as an mp3 file.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path"
                },
                "fps": {
                  "type": ["integer", "null"],
                  "description": "Frames per second (fps) to extract from the video. If omitted, the default value of 1 fps will be used."
                }
              },
              "required": ["file", "fps"],
              "additionalProperties": false
            }
          },
          "strict": true
        },
        {
          "type": "function",
          "function":
          {
            "name": "analyze_video",
            "description": "Analyze the video content and provide a description of the contents of the video. The function takes the JSON file containing the list of base64 images of the frames extracted from the video as input.",
            "parameters": {
              "type": "object",
              "properties": {
                "json_file": {
                  "type": "string",
                  "description": "File name or file path of the json file containing the list of base64 images of the frames extracted from the video"
                },
                "audio_file": {
                  "type": ["string", "null"],
                  "description": "File name or file path of the audio mp3 extracted from the video. If no audio is available, this parameter can be omitted."
                },
                "query": {
                  "type": ["string", "null"],
                  "description": "Query to be used for generating the description of the video content. If omitted, a default query 'What is happening in the video?' will be used."
                }
              },
              "required": ["json_file", "audio_file", "query"],
              "additionalProperties": false
            }
          },
          "strict": true
        }
      ]
    }
  end
end
