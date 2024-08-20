class ImageGeneration < MonadicApp
  icon = "<i class='fa-regular fa-image'></i>"

  description = <<~TEXT
    This is an app that generates images based on a description. If the prompt is not concrete enough or if it is written in a language other than English, the app will return an improved prompt and ask if the user wants to proceed with the improved prompt."
  TEXT

  initial_prompt = <<~TEXT
    You help the user create images generated by Dall-E 3. You conduct the following process step-by-step.

    - Call the `generate_image` function with the user's text prompt.
    - Retrieve the `revised_prompt` and `filename` values from the response JSON.
    - Embed these values to REVISED_PROMPT and FILENAME, respectively, in the HTML template below and return it to the user.

    <div>
      <p class="revised_prompt">
        <b>Revised Prompt</b>: REVISED_PROMPT
      </p>
    </div>
    <div class="generated_image">
      <img src="/data/FILENAME">
    </div>

    Remember that `generate_image` function will call the Dall-E 3 model to generate a revised prompt and an image based on the revised prompt.

    If the user asks you to add something to generated images or to modify them, re-generate another image by calling the `generate_image` function with an extended or modified prompt and discarding the old ones. Do not modify an existing image itself directly—just ignore the image URLs included in the previous message.

    In case `generate_image` fails, return a detailed error message to the user, not retrying the process. If the user asks you to retry, you can do so by calling the `generate_image` function again with a prompt that you have modified according to the error message.

    If an error occurs as a result of calling the `generate_image` function, return the error message to the user without retrying the process. If the user asks you to retry, you can do so by calling the `generate_image` function again with a prompt that you have modified according to the error message.
  TEXT

  @settings = {
    app_name: "Image Generator",
    model: "gpt-4o-mini",
    temperature: 0.0,
    top_p: 0.0,
    max_tokens: 4000,
    context_size: 20,
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image: true,
    image_generation: true,
    tools: [{
      type: "function",
      function: {
        name: "generate_image",
        description: "Generate an image based on a description.",
        parameters: {
          type: "object",
          properties: {
            prompt: {
              type: "string",
              description: "The prompt to generate an image from."
            },
            size: {
              type: "string",
              enum: ["1024x1024", "1024x1792", "1792x1024"],
              description: "The size of the generated image."
            }
          },
          required: ["prompt", "size"],
          additionalProperties: false
        }
      },
      strict: true
    }]
  }
end
