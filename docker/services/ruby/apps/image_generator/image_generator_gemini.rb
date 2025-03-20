class ImageGeneratorGeminiApp < MonadicApp
    include GeminiHelper

    icon = "<i class='fa-regular fa-image'></i>"

    description = <<~TEXT
      This app generates images using Google's Imagen model through the Gemini API. It supports various aspect ratios and can generate multiple images at once. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=image-generator" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
    TEXT

    initial_prompt = <<~TEXT
      You help users create images using Google's Imagen model. 
      
      EXTREMELY IMPORTANT: Never use markdown code blocks (```) in your responses. Output pure HTML without any code markers.
      
      Follow this process for each request:

      1. If the user's prompt is not in English, politely translate it to English while preserving all creative details. The prompt may be given with the context from preceding messages. In that case, create a new prompt that includes the context and the new request.
      
      2. Call the `generate_image_with_imagen` function with appropriate parameters:
         - prompt: The English version of the user's request (required)
         - aspect_ratio (specify "1:1", "3:4", "4:3", "9:16", or "16:9")
         - sample_count: Number of images to generate (1)
         - person_generation: Setting for generating people (always "ALLOW_ADULT")
      
      3. Analyze the function response:
         - If there's an error, explain it to the user
         - If successful, look for lines like "Successfully saved image to: /path/to/1234567_0_1x1.png"
         - Extract JUST the filename from these paths (e.g., "1234567_0_1x1.png")
         
      4. AFTER function execution, IMMEDIATELY output raw HTML with NO MARKDOWN CODE BLOCKS OR BACKTICKS
      
      4. For successful generations, ALWAYS use EXACTLY this template to display the result (replace only the variable parts inside curly braces):
         
         <div>
           <p class="prompt">
             <b>Prompt</b>: {original_prompt}
           </p>
         </div>
         <div class="generated_image">
           <img src="/data/{filename}">
         </div>
         
      CRITICAL: Images will not display unless you follow these exact instructions:
      
      1. When you get the response from `generate_image_with_imagen`, ANALYZE THE ENTIRE OUTPUT TEXT carefully
      2. Look for successful image generation patterns like "Successfully saved image to: /path/to/TIMESTAMP_INDEX_ASPECTRATIO.png"
      3. EXTRACT THE FILENAME from this path (e.g. "1742189412_0_1x1.png")
      4. Replace {original_prompt} with the text of the original prompt you sent
      5. Replace {filename} with each extracted filename
      
      For successful generations, you MUST ONLY RESPOND with the exact HTML shown below (NEVER enclosed in backticks):
      
      <div>
        <p class="prompt">
          <b>Prompt</b>: A dog on the beach
        </p>
      </div>
      <div class="generated_image">
        <img src="/data/1711234567_0_1x1.png">
      </div>
      
    TEXT

    # Using self.settings = instead of @settings = for proper class variable definition
    @settings = {
      group: "Google",
      app_name: "Image Generator (Gemini)",
      disabled: !CONFIG["GEMINI_API_KEY"],
      models: GeminiHelper.list_models,
      model: "gemini-2.0-flash", # Using an appropriate Gemini model
      temperature: 0.2, # Slightly higher to allow for creative responses
      initial_prompt: initial_prompt,
      description: description,
      icon: icon,
      easy_submit: false,
      auto_speech: false,
      initiate_from_assistant: false,
      image_generation: true,
      tools: {
        function_declarations: [
          {
            name: "generate_image_with_imagen",
            description: "Generate images using Google's Imagen model.",
            parameters: {
              type: "object",
              properties: {
                prompt: {
                  type: "string",
                  description: "The prompt to generate an image from (should be in English for best results)."
                },
                aspect_ratio: {
                  type: "string",
                  enum: ["1:1", "3:4", "4:3", "9:16", "16:9"],
                  description: "The size of the generated image (square, portrait, or landscape)."
                },
                sample_count: {
                  type: "integer",
                  description: "Number of images to generate (1-4).",
                  minimum: 1,
                  maximum: 4
                },
                person_generation: {
                  type: "string",
                  enum: ["ALLOW_ADULT"],
                  description: "Controls whether to allow generating images of people."
                }
              },
              required: ["prompt"]
            }
          }
        ]
      }
    }
  end
