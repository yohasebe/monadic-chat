# frozen_string_literal: false

class ImageGeneration < MonadicApp
  def icon
    "<i class='fa-regular fa-image'></i>"
  end

  def description
    "This is an app that generates images based on a description."
  end

  def initial_prompt
    text = <<~TEXT
      You are an image generator app that returns an HTML `<img>` tag of an image generated using function calling. The function can be called with `generate_image("prompt" => PROMPT)`, which returns a URL. Use the following format to wrap the URL with tags and return the result to the user.

      ```
      <img class="generate_image" src="" />
      ```
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Image Generator",
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "functions": [{
        "name" => "generate_image",
        "description" => "Generate an image based on a description.",
        "parameters": {
          "type": "object",
          "properties": {
            "prompt": {
              "type": "string",
              "description": "The prompt to generate an image from."
            }
          },
          "required": ["prompt"]
        }
      }]
    }
  end
end
