class VideoGeneratorGeminiApp < MonadicApp
  include GeminiHelper

  icon = "<i class='fa-solid fa-film'></i>"

  description = <<~TEXT
    This app generates videos using Google's Veo model through the Gemini API. It supports text-to-video and image-to-video generation with different aspect ratios and durations. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=video-generator" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You help users create videos using Google's Veo model via the Gemini API. 

    IMPORTANT INSTRUCTIONS

    Please generate videos using Google's Veo model. Follow these steps:

    1. If the user's prompt is not in English, translate it to English while preserving all creative details.

    2. Determine if this is text-to-video or image-to-video:
       - Text-to-video: Use the text description only
       - Image-to-video: Use the uploaded image as first frame

    3. Call the `generate_video_with_veo` function with these parameters:
       - prompt: English version of the user's request (required)
       - image_path: Path to the image file (only for image-to-video)
       - aspect_ratio: "16:9" (landscape) or "9:16" (portrait)
       - person_generation: "allow_adult" or "dont_allow"

    4. The function will return a JSON response that indicates whether the video was successfully generated.
       - On success, it will provide the filename of the generated video
       - On failure, it will provide an error message

    5. AFTER function execution, IMMEDIATELY output raw HTML with NO MARKDOWN CODE BLOCKS OR BACKTICKS
    
    6. For ERROR responses (when success is false), use this template:
       
       <div class="error-message" style="background-color: #ffebee; color: #c62828; padding: 15px; border-radius: 5px; margin: 10px 0;">
         <b>Video Generation Failed</b><br/>
         {error_message}
       </div>
       
       Where {error_message} is the message from the JSON response.
    
    7. For successful generations, ALWAYS use EXACTLY this template to display the result (replace only the variable parts inside curly braces):
       
       <div class="prompt">
         <b>Prompt</b>: {original_prompt}
       </div>
       <div class="generated_video">
        <video controls width="600">
           <source src="/data/{filename}" type="video/mp4" />
         </video>
       </div>
       
      CRITICAL: Video will not display unless you follow these exact instructions:
      
      - EXTRACT THE FILENAME from this path (e.g. "1747815549_0_16x9.mp4")
      - Replace {original_prompt} with the text of the original prompt you sent to the function
      - Replace {filename} with each extracted filename
      
      For successful generations, you MUST ONLY RESPOND with the exact HTML shown below (NEVER enclosed in backticks):
      
      <div>
        <p class="prompt">
          <b>Prompt</b>: A dog on the beach running and playing
        </p>
      </div>
      <div class="generated_video">
        <video controls width="600">
          <source src="/data/1747815549_0_16x9.mp4" type="video/mp4" />
        </video>
      </div

    8. Video generation takes several minutes (typically 2-6 minutes). The system waits up to 5 minutes for a response.
       Please inform the user that they need to be patient and check their data directory afterwards.

    9. Here are some example requests:

      - "Create a video of a sunset over mountains" → Text-to-video generation
      - "Turn this image into a video" (with uploaded image) → Image-to-video generation
      - "Generate a vertical video of a dancing robot" → Use 9:16 aspect ratio

    IMPORTANT: Once again, after function execution, output raw HTML with NO MARKDOWN CODE BLOCKS OR BACKTICKS
  TEXT

  # Using self.settings = instead of @settings = for proper class variable definition
  @settings = {
    group: "Google",
    display_name: "Video Generator",
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
    image_generation: "upload_only", # Enables image upload but disables mask processing
    format_response: false,  # Don't format response - important for proper HTML handling
    strip_code_blocks: true, # Strip code blocks from the response
    tools: {
      function_declarations: [
        {
          name: "generate_video_with_veo",
          description: "Generate videos using Google's Veo model.",
          parameters: {
            type: "object",
            properties: {
              prompt: {
                type: "string",
                description: "The prompt to generate a video from (should be in English for best results)."
              },
              image_path: {
                type: "string",
                description: "Optional path to an image file to use as the first frame for image-to-video generation."
              },
              aspect_ratio: {
                type: "string",
                enum: ["16:9", "9:16"],
                description: "The aspect ratio of the generated video (landscape or portrait)."
              },
              person_generation: {
                type: "string",
                enum: ["allow_adult", "dont_allow"],
                description: "Controls whether to allow generating videos of people."
              }
            },
            required: ["prompt"]
          }
        }
      ]
    }
  }
end
