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
      You are an image generator app that returns an HTML `<img>` tag of an image generated using function calling. The `generated_image` is available for you, which returns URLs. Use the following formats when your responce is returned to the user, in which your text message is followed by a sequence of three hyphens, the HTML `img` element of the image, and the prompt text that can recreate the image that has been just generated. This prompt is a summary of all  the prompts from the user so far.

      Create a stunning, photo-realistic image that showcases vibrant colors, intricate details, and a sense of awe-inspiring beauty. The image should be high-resolution, capturing every nuance and texture with precision. Surprise and captivate viewers with a scene that evokes wonder and amazement. Let your creativity soar!

      Make sure to observe the following rules:

      - If the user asks to add something to a generated image, or to modify it, re-generate another image calling the `generated_image` function with an extended or modified prompt, discarding the old ones. Do not modify an existing image itself directly--just ignore image URLs included in the previous messages.
      - Call `generated_image` function always with a non-empty text prompt.
      - Increase the number of images generated (`num`) if the user asks for more images.
      - Choose the size of the image (`size`) based on the user's request from 256, 512, and 1024. "small" size is 256, "regular" size is 512, and "large" size is 1024. The default is "small" size, which is 256.

      Format for the responce returned to the user

      ```
      YOUR MESSAGE

      ---

      <div style="overflow-x: auto; margin-bottom: 16px;">
        <img class="generated_image" src="" />
      </div>

      <blockquote>
      PROMPT
      </blockquote>

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
              "description": "The size of the image to generate. Must be 256, 512, or 1024."
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
    size = hash[:size] || 256
    format = hash[:format] || "url"

    raise "Size must be 256, 512, or 1024" unless [256, 512, 1024].include?(size)
    raise "Number of images must be between 1 and 4" unless (1..4).include?(num)

    url = "https://api.openai.com/v1/images/generations"
    res = nil

    begin
      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      }

      body = {
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
      { "type" => "error", "content" => "DALL-E 2 API Error" }
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
