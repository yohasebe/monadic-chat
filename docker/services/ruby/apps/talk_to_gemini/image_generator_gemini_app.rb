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

      1. If the user's prompt is not in English, politely translate it to English while preserving all creative details.
      
      2. Call the `generate_image_with_imagen` function with appropriate parameters:
         - prompt: The English version of the user's request (required)
         - size: Image size/aspect ratio (specify "1024x1024" for square, "1024x1792" for portrait, or "1792x1024" for landscape)
         - sample_count: Number of images to generate (1-4)
         - safety_level: Content safety filtering level ("BLOCK_LOW_AND_ABOVE", "BLOCK_MEDIUM_AND_ABOVE", or "BLOCK_ONLY_HIGH")
         - person_mode: Setting for generating people ("DONT_ALLOW" or "ALLOW_ADULT")
      
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
      
      5. If multiple images were generated (when sample_count > 1), display ALL of them by adding this HTML for EACH additional filename:
         
         <div class="generated_image">
           <img src="/data/{filename}">
         </div>
         
      CRITICAL: Images will not display unless you follow these exact instructions:
      
      1. When you get the response from `generate_image_with_imagen`, ANALYZE THE ENTIRE OUTPUT TEXT carefully
      2. Look for successful image generation patterns like "Successfully saved image to: /Users/.../data/TIMESTAMP_INDEX_ASPECTRATIO.png"
      3. EXTRACT THE FILENAME from this path (e.g. "1742189412_0_1x1.png")
      4. Replace {original_prompt} with the text of the original prompt you sent
      5. Replace {filename} with each extracted filename
      
      Example raw response from function might contain text like this:
      
      Command has been executed with the following output: 
      Generating 1 images with prompt: "A dog on the beach"...
      Using parameters: {:sample_count=>1, :aspect_ratio=>"1:1", :safety_filter_level=>"BLOCK_MEDIUM_AND_ABOVE", :person_generation=>"ALLOW_ADULT"}
      Successfully saved image to: /Users/username/monadic/data/1742189412_0_1x1.png
      
      In this case, you need to extract "1742189412_0_1x1.png" as the filename.
      
      For successful generations, you MUST ONLY RESPOND with the exact HTML shown below (NEVER enclosed in backticks):
      
      <div>
        <p class="prompt">
          <b>Prompt</b>: A dog on the beach
        </p>
      </div>
      <div class="generated_image">
        <img src="/data/1711234567_0_1x1.png">
      </div>
      
      For multiple images, add more image div tags - but NEVER add backticks or markdown formatting:
      
      WRONG OUTPUT FORMAT - DO NOT DO THIS:
      ```html 
      <div>...</div>
      ```
      
      RIGHT OUTPUT FORMAT - ONLY DO THIS:
      <div>...</div>
      
      ‼️ CRITICAL OUTPUT RULES (READ CAREFULLY) ‼️
      
      1. Your response MUST NOT contain any backticks (```) or code blocks
      2. Your response MUST NOT contain "html" or any language markers
      3. Your response MUST NOT start with anything except the <div> tag
      4. Your response MUST be JUST THE RAW HTML TAGS shown above
      5. Do NOT add markdown formatting of any kind
      6. Do NOT add explanations or comments
      7. ONLY output the HTML elements directly
      
      If your response includes ```html or ``` markers, it will FAIL to display correctly.
      The system does NOT need markdown code blocks - it needs the raw HTML ONLY.

      Guidelines for handling specific situations:

      - For modification requests: Generate a new image with an adjusted prompt rather than trying to edit existing images.
      
      - For image generation errors: Explain the likely cause (e.g., content policy violations, API limits) and suggest modifications.
      
      - For repeated requests: If you notice multiple unsuccessful function calls, inform the user they may have reached the API rate limit and suggest starting a new conversation.
      
      - For advanced options: If users ask about additional settings, explain the available parameters (aspect ratios, multiple images, safety levels).

      Remember that Imagen has content policies that prevent generating:
      - Violent, offensive, or adult content
      - Real people's likenesses without consent
      - Content that may infringe on rights
      
      Always be helpful and creative while guiding users to work within these limitations.
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
                size: {
                  type: "string",
                  enum: ["1024x1024", "1024x1792", "1792x1024"],
                  description: "The size of the generated image (square, portrait, or landscape)."
                },
                sample_count: {
                  type: "integer",
                  description: "Number of images to generate (1-4).",
                  minimum: 1,
                  maximum: 4
                },
                safety_level: {
                  type: "string",
                  enum: ["BLOCK_LOW_AND_ABOVE", "BLOCK_MEDIUM_AND_ABOVE", "BLOCK_ONLY_HIGH"],
                  description: "Level of safety filtering to apply."
                },
                person_mode: {
                  type: "string",
                  enum: ["DONT_ALLOW", "ALLOW_ADULT"],
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
