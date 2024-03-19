# frozen_string_literal: false

class DocumentReader < MonadicApp
  def icon
    "<i class='fab fa-leanpub'></i>"
  end

  def description
    "This application features an AI chatbot designed to simplify and elucidate the contents of any imported document or web URL. The explanations are presented in an accessible and beginner-friendly manner. Users have the flexibility to upload files or URLs encompassing a wide array of text data, including programming code. The data from the imported file is appended to the end of the system prompt, incorporating the title specified during import. When URLs are mentioned in your prompt messages, the app automatically retrieves the content, seamlessly integrating it into the conversation with GPT."
  end

  def initial_prompt
    text = <<~TEXT
      You are a professional tutor who explains various concepts in a fashion that is very easy for even beginners to understand in whatever language the user is comfortable with.

      The user may provide a specific web URL. In that case, you fetch the content of the web page using the `fetch_web_content` function. The function takes the URL of the web page as the parameter and returns itscontents. Alternatively, the user can uploaded a document, the contents  of the user uploaded document, if any, will be appended at the end of the system prompt.

      Your explanation is made in a step-by-step fashion, where you first show a snippet of it, then give a very easy-to-understand description of what it says or does. Then, you list all the relevant concepts, terms, functions, etc. and give a brief description to each of them. In your explanation, please use visual illustrations using Mermaid and mathematical expressions using MathJax where possible. Please make your explanation as easy-to-understand as possible using appropriate and creative analogies that help the user understand the code well. Here is the basic structure of one of your responses:

      - SNIPPET_OF_DOCUMENT
      - EXPLANATION
      - BASIC_CONCEPTS_AND_TERMS

      Stop your text after presenting an explanation about one paragrah, text block, or code block. If the user questions something relevant to the code, answer it. Remember to explain as kindly and friendly as possible.

      When your response includes a mathematical notation, please use the MathJax notation with `$$` as the display delimiter and with `$` as the inline delimiter. For example, if you want to write the square root of 2 in a separate block, you can write it as $$\\sqrt{2}$$. If you want to write it inline, write it as $\\sqrt{2}$. Remember to use these formats to write mathematical notations in your response. Do not use a simple `\\` as the delimiter for the mathematical notation.

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
      "context_size": 12,
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
        }
      ]
    }
  end

  def fetch_web_content(hash)
    begin
      url = hash[:url].to_s.strip rescue ""
      shared_volume = "/monadic/data/"
      conda_container = "monadic-chat-conda-container"
      command = "bash -c '/monadic/web_content_fetcher.py --url \"#{url}\" --filepath \"#{shared_volume}\" --mode \"md\" '"
      docker_command =<<~DOCKER
        docker exec -w #{shared_volume} #{conda_container} #{command}
      DOCKER
      stdout, stderr, status = Open3.capture3(docker_command)
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]
        contents = File.read(filename)
        contents
      else
        "Error occurred: #{stderr}"
      end
    rescue StandardError => e
      "Error occurred: #{stderr}"
    end
  end
end
