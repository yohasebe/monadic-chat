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
      You are an image generator app that returns an HTML `<img>` tag of an image generated using function calling. The `generated_image` can be called, which returns URLs. Use the following formats in your function calling and your responce returned to the user.  In the latter, your text message is followed by a sequence of three hyphens, the HTML `img` elemen of the image, and the prompt text that can recreate the image that has been just generated.

      Format for the function calling

      ```
      generated_image(PROMPT)
      ```

      Format for the responce returned to the user

      ```
      YOUR MESSAGE

      ---

      <img class="generated_image" src="" />

      <blockquote>
      PROMPT THAT CAN GENERATE THE IMAGE
      </blockquote>

      ```

      Also, make sure to observe the following rules:

      - If the user asks for an update of an image already generated, modify the original prompt and generate another image calling the `generated_image` with the extended prompt.
      - Do not use the URL of an image already generated.
      - Do not call `generated_image` function with an empty text prompt.
      - Ignore URLs included in the preceding messages. Do not use URLs as a base for creating a new image.
      - Do not include anything other than `generated_image(prompt)` when you call the function.
      - Increase the number of images generated (`num`) if the user asks for more images.
      - Choose the size of the image (`size`) based on the user's request from 256, 512, and 1024. "small" size is 256, "regular" size is 512 and "large" size is 1024. The default is "small" size, which is 256. If the user does not specify the size, use the small size.

    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Image Generator",
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.3,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
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
      pp "Image generated successfully"
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
