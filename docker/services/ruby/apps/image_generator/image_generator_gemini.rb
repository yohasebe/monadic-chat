class ImageGeneratorGeminiApp < MonadicApp
    include GeminiHelper

    icon = "<i class='fa-regular fa-image'></i>"

    description = <<~TEXT
      This app generates and edits images using Google's AI models. For image generation, it automatically selects between Imagen 3 (high-quality, photorealistic) and Gemini 2.0 Flash (versatile, fast) based on your requirements. For image editing, it uses Gemini 2.0 Flash which supports natural language-based editing of uploaded images. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=image-generator" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
    TEXT

    initial_prompt = <<~TEXT
      You help users create and edit images using Google's AI models (Imagen 3 and Gemini 2.0 Flash). 
      
      EXTREMELY IMPORTANT: Never use markdown code blocks (```) in your responses. Output pure HTML without any code markers.
      
      Follow this process for each request:

      1. Determine if this is image generation or editing:
         - If no image is uploaded: Use text-to-image generation
         - If an image is uploaded: Use image editing

      2. If the user's prompt is not in English, politely translate it to English while preserving all creative details.
      
      3. For TEXT-TO-IMAGE generation, call `generate_image_with_gemini` function with:
         - prompt: The English version of the user's request (required)
         - operation: "generate"
         - model: Choose between "imagen3" (high quality, precise) or "gemini" (versatile, fast)
      
      4. For IMAGE EDITING (when an image is uploaded), call `generate_image_with_gemini` function with:
         - prompt: The English version of the editing instructions (required)
         - operation: "edit"
         
      5. Analyze the function response:
         - Check the "success" field in the JSON response
         - If success is true, extract the filename from the "filename" field
         - If success is false, display the error message from the "error" field
         - Check the "model" field to show which model was used
         
      6. AFTER function execution, IMMEDIATELY output raw HTML with NO MARKDOWN CODE BLOCKS OR BACKTICKS
      
      CRITICAL: You MUST parse the JSON response from the function and display the result.
      Even if the model is "imagen3", you MUST still display the image using the template above.
      
      7. For successful operations, ALWAYS use EXACTLY this template to display the result:
         
        <div class="prompt">
          <b>{operation_type}</b> (using {model_name}): {original_prompt}
        </div>
        <div class="generated_image">
          <img src="/data/{filename}">
        </div>
         
      Where:
      - {operation_type} is "Generated Image" for new images or "Edited Image" for edits
      - {model_name} is "Imagen 3" if model is "imagen3", or "Gemini 2.0 Flash" if model is "gemini"
      - {original_prompt} is the text of the prompt you sent
      - {filename} is the filename from the JSON response
      
      8. For errors, use this template:
         
        <div class="error-message" style="background-color: #ffebee; color: #c62828; padding: 15px; border-radius: 5px; margin: 10px 0;">
          <b>Image {Operation} Failed</b><br/>
          {error_message}
        </div>
        
      Examples:
      - "Create an image of a sunset over mountains" → Text-to-image generation (choose model)
      - "Make the sky more purple" (with uploaded image) → Image editing (always uses Gemini)
      - "Add a rainbow to this photo" (with uploaded image) → Image editing (always uses Gemini)
      
      Model Selection Guidelines for Image Generation:
      - Use "imagen3" for: photorealistic images, portraits, detailed landscapes, professional quality, commercial use
      - Use "gemini" for: creative art, illustrations, concept art, quick iterations, experimental styles
      
      Image Editing:
      - Always uses Gemini 2.0 Flash (only model with editing capabilities)
      - Supports natural language instructions like "make the sky purple" or "add a rainbow"
      
    TEXT

    # Using self.settings = instead of @settings = for proper class variable definition
    @settings = {
      group: "Google",
      display_name: "Image Generator",
      disabled: !CONFIG["GEMINI_API_KEY"],
      models: GeminiHelper.list_models,
      model: "gemini-2.0-flash", # Using Gemini model for instructions
      temperature: 0.2, # Slightly higher to allow for creative responses
      initial_prompt: initial_prompt,
      description: description,
      icon: icon,
      easy_submit: false,
      auto_speech: false,
      initiate_from_assistant: false,
      image_generation: "upload_only", # Enable image upload for editing
      format_response: false,  # Don't format response - important for proper HTML handling
      strip_code_blocks: true, # Strip code blocks from the response
      tools: {
        function_declarations: [
          {
            name: "generate_image_with_gemini",
            description: "Generate or edit images using Google's Gemini 2.0 Flash model.",
            parameters: {
              type: "object",
              properties: {
                prompt: {
                  type: "string",
                  description: "The prompt to generate an image from or editing instructions (should be in English for best results)."
                },
                operation: {
                  type: "string",
                  enum: ["generate", "edit"],
                  description: "Operation type: 'generate' for new images, 'edit' for modifying existing images."
                },
                model: {
                  type: "string",
                  enum: ["imagen3", "gemini"],
                  description: "Model to use: 'imagen3' for high-quality photorealistic images, 'gemini' for versatile generation and editing capability."
                }
              },
              required: ["prompt", "operation"]
            }
          }
        ]
      }
    }
  end
