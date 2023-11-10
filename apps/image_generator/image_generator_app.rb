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

      If either the two conditions below is not met, return an improved prompt of more than 150 words in English that can create a high-quality image and ask the user if the user wants to generate images using it.

      - The prompt is written in English
      - The prompt is concrete and long enough (more than 150 words)

      Here is the format for the response returned to the user when the prompt is improved:

      ```
      Here is an improved prompt: 

      > IMPROVED PROMPT

      Do you want to proceed with this prompt?
      ```

      Only when the both rules above are followed, do the following:

      - Call the `generate_image` function always with a non-empty text prompt.
      - Increase the number of images generated (`num`) if the user asks for more images.
      - Choose the size of the image (`size`) based on the user's request from 1024x1024, 1024x1792, 1792x1024. "small" size is 1024x1024, "regular" size is 1024x1792, and "large" size is 1792x1024.
      - If the user does not specify the number of images to generate, create two images by setting 2 to the `num` parameter and 256 to the `size` parameter.
      - If the user asks to add something to generated images or to modify it, re-generate another image, calling the `generate_image` function with an extended or modified prompt, discarding the old ones. Do not modify an existing image itself directly--just ignore image URLs included in the previous messages. Show the modified prompt in the response.

      Here is the format for the response returned to the user when the images are generated:

      ```
      <div style="overflow-x: auto; margin-bottom: 16px;">
        <img class="generated_image" src="" />
      </div>

      <div style="overflow-x: auto; margin-bottom: 16px;">
        <img class="generated_image" src="" />
      </div>
      ```

    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Image Generator",
      "model": "gpt-3.5-turbo",
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
      "function_call": { "name": "generate_image" },
      "functions": [{
        "name" => "generate_image",
        "description" => "Generate an image based on a description.",
        "parameters": {
          "type": "object",
          "properties": {
            "prompt": {
              "type": "string",
              "description": "The prompt to generate an image from."
            },
            "num": {
              "type": "integer",
              "description": "The number of images to generate. Must be between 1 and 4."
            },
            "size": {
              "type": "integer",
              "description": "The size of the image to generate. Must be 1024x1024, 1024x1792, or 1792x1024"
            }
          },
          "required": ["prompt"]
        }
      }]
    }
  end

  def generate_image(hash, num_retrials: 10)
    prompt = hash[:prompt]
    num = hash[:num] || 1
    size = hash[:size] || "1024x1024"
    format = hash[:format] || "url"

    raise "Size must be 1024x1024, 1024x1792, 792x1024" unless ["1024x1024", "1024x1792", "1792x1024"].include?(size)
    raise "Number of images must be between 1 and 4" unless (1..4).include?(num)

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
        "n" => num,
        "size" => "#{size}x#{size}",
        "response_format" => format
      }

      res = HTTP.headers(headers).post(url, json: body)
    rescue HTTP::Error, HTTP::TimeoutError => e
      return { "type" => "error", "content" => "ERROR: #{e.message}" }
    end

    if res.status.success?
      img = JSON.parse(res.body)
      img["data"].map do |i|
        "<img class='generate_image' src='#{i["url"]}' />"
      end.join("\n")
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
