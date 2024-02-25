# frozen_string_literal: false

class ImageGeneration < MonadicApp
  def icon
    "<i class='fa-regular fa-image'></i>"
  end

  def description
    "This is an app that generates images based on a description. If the prompt is not concrete enough or if it is written in a language other than English, the app will return an improved prompt and asks if the user wants to proceed with the improved prompt."
  end

  def initial_prompt
    text = <<~TEXT
      You are a prompt enhancer and image generator app. You conduct the following process step-by-step.

      - Call the `generate_image` function with the user's text prompt.
      - Retrieve the `revised_prompt` and `image_url` from the response.
      - Embed these values to the HTML template below and return it to the user.

      ```
      <div style="margin-bottom: 16px;">
        <p class="revised_prompt"></p>
      </div>

      <div style="margin-bottom: 16px;">
        <img style="max-width: 100%;" class="generated_image" src="" />
      </div>
      ```

      If the user asks to add something to generated images or to modify it, re-generate another image, calling the `generate_image` function with an extended or modified prompt, discarding the old ones. Do not modify an existing image itself directly--just ignore image URLs included in the previous message.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Image Generator",
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 4,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "image_generation": true,
      "tools": [{
        "type": "function",
        "function": {
          "name": "generate_image",
          "description": "Generate an image based on a description.",
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
        }
      }]
    }
  end

  def generate_image(hash, num_retrials: 10)
    prompt = hash[:prompt]
    format = hash[:format] || "url"

    url = "https://api.openai.com/v1/images/generations"
    res = nil

    begin
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      }

      body = {
        "model" => "dall-e-3",
        "prompt" => prompt,
        "n" => 1,
        "size" => "1792x1024",
        "response_format" => format
      }

      res = HTTP.headers(headers).post(url, json: body)
    rescue HTTP::Error, HTTP::TimeoutError => e
      return { "type" => "error", "content" => "ERROR: #{e.message}" }
    end

    if res.status.success?
      res.body
    else
      pp "Error: #{res.status} - #{res.body}"
      { "type" => "error", "content" => "DALL-E 3 API Error" }
    end
  rescue StandardError => e
    pp e.message
    pp e.backtrace
    num_retrials -= 1
    if num_retrials.positive?
      sleep 1
      generate_image(hash, num_retrials: num_retrials)
    else
      <<~TEXT
        "SEARCH SNIPPETS: ```
        information not found"
        ```
      TEXT
    end
  end
end
