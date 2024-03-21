# frozen_string_literal: false

require "uri"

class DocumentReader < MonadicApp
  def icon
    "<i class='fab fa-leanpub'></i>"
  end

  def description
    "This application features an AI chatbot designed to simplify and elucidate the contents of any imported document or web URL. The explanations are presented in an accessible and beginner-friendly manner. Users have the flexibility to upload files or URLs encompassing a wide array of text data, including programming code. The data from the imported file is appended to the end of the system prompt, incorporating the title specified during import. When URLs are mentioned in your prompt messages, the app automatically retrieves the content, seamlessly integrating it into the conversation with GPT."
  end

  def initial_prompt
    text = <<~TEXT
      You are a professional teacher who explains various concepts in an extremely way for even beginners in the field. You can use whatever language that the user is comfortable with.

      The user may provide a specific web URL. In that case, you fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns itscontents.

      Alternatively, the user may give you the name of a specific file available in your current environment. In that case, use the `fetch_text_from_file` function to fetch the text from the file and return its content. The function takes the file name or file path as the parameter and returns its content.

      In either case, you should extract only the relevant text data from the web page or file and explain it in a beginner-friendly manner. The page or file may contain a wide array of metadata, such as HTML tags, CSS, JavaScript, etc., which should be ignored. You should only focus on the main content of the page or file.

      Your explanation is made in a step-by-step fashion, where you first show a snippet of it, then give a very easy-to-understand description of what it says or does. Then, you list all the relevant concepts, terms, functions, etc. and give a brief description to each of them. Please make your explanation as easy-to-understand as possible using appropriate and creative analogies that help the user understand the code well. Here is the basic structure of one of your responses:

      - SNIPPET_OF_DOCUMENT
      - EXPLANATION
      - BASIC_CONCEPTS_AND_TERMS

      Stop your text after presenting an explanation about one paragrah, text block, or code block. If the user questions something relevant to the code, answer it. Remember to explain as kindly and friendly as possible.

      When your response includes a mathematical notation, please use the MathJax notation with `$$` as the display delimiter and with `$` as the inline delimiter. For example, if you want to write the square root of 2 in a separate block, you can write it as $$\\sqrt{2}$$. If you want to write it inline, write it as $\\sqrt{2}$. Remember to use these formats to write mathematical notations in your response. Do not use a simple `\\` as the delimiter for the mathematical notation.

      If the user requests an explanation of a specific image, you can use the `analyze_image` function to analyze the image and return the result. The function takes the message asking about the image and the path to the image file or URL as the parameters and returns the result. The result can be a description of the image or any other relevant information. In your response, present the text description and the <img> tag to display the image (e.g. `<img src="FILE_NAME" />`).

      If the user provides an audio file, you can use the `analyze_speech` function to analyze the speech and return the result. The function takes the file path of the audio file as the parameter and returns the result. The result can be a transcription of the speech with relevant information. In your response, present the text transcription and the <audio> tag to play the audio (`<audio controls src="FILE_NAME"></audio>`).

      If there is no data to explain, please tell the user and ask the user to provide a document or a URL.
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4-0125-preview",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Document Reader",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
      "pdf": false,
      "mathjax": true,
      "file": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "fetch_web_content",
            "description": "Fetch the content of a web page and return its content.",
            "parameters": {
              "type": "object",
              "properties": {
                "url": {
                  "type": "string",
                  "description": "URL of the web page."
                }
              },
              "required": ["url"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "analyze_image",
            "description": "Analyze the image and return the result.",
            "parameters": {
              "type": "object",
              "properties": {
                "message": {
                  "type": "string",
                  "description": "Text prompt asking about the image (e.g. 'What is in the image?')."
                },
                "image_path": {
                  "type": "string",
                  "description": "Path to the image file. It can be either a local file path or a URL."
                }
              },
              "required": ["message", "image_path"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "analyze_speech",
            "description": "Analyze the speech and return the result.",
            "parameters": {
              "type": "object",
              "properties": {
                "audio": {
                  "type": "string",
                  "description": "File path of the audio file"
                }
              },
              "required": ["audio"]
            }
          }
        },
        {
          "type": "function",
          "function":
          {
            "name": "fetch_text_from_file",
            "description": "Fetch the text from a file and return its content.",
            "parameters": {
              "type": "object",
              "properties": {
                "file": {
                  "type": "string",
                  "description": "File name or file path"
                }
              },
              "required": ["file"]
            }
          }
        }
      ]
    }
  end

  def fetch_web_content(hash)
    begin
      url = hash[:url].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      container = "monadic-chat-python-container"
      command = "bash -c '/monadic/scripts/web_content_fetcher.py --url \"#{url}\" --filepath \"#{shared_volume}\" --mode \"md\" '"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{container} #{command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]
        sleep(1)
        begin
          contents = File.read(filename)
        rescue StandardError => e
          filepath = File.join(File.expand_path("~/monadic/data/"), File.basename(filename))
          contents = File.read(filepath)
        end
        contents
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
  end

  def analyze_image(hash)
    begin
      message = hash[:message].to_s.strip rescue ""
      messsage = message.gsub(/"/, '\"')
      image_path = hash[:image_path].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      container = "monadic-chat-python-container"
      command = <<~CMD
        bash -c '/monadic/scripts/simple_image_query.rb "#{message}" "#{image_path}"'
      CMD
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{container} #{command.strip}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        stdout
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
  end

  def analyze_speech(hash)
    begin
      shared_volume = "/monadic/data/"
      audio = hash[:audio].to_s.strip rescue ""
      audio = File.join(shared_volume, File.basename(audio))
      container = "monadic-chat-python-container"
      command = <<~CMD
        bash -c '/monadic/scripts/simple_whisper_query.rb "#{audio}" "#{shared_volume}"'
      CMD
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{container} #{command.strip}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        stdout
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
  end

  def fetch_text_from_file(hash)
    begin
      shared_volume = "/monadic/data/"
      file = hash[:file].to_s.strip rescue ""
      file = File.join(shared_volume, File.basename(file))
      container = "monadic-chat-python-container"
      command = <<~CMD
        bash -c '/monadic/scripts/simple_content_fetcher.rb "#{file}"'
      CMD
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{container} #{command.strip}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        stdout
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{e.message}"
    end
  end
end
