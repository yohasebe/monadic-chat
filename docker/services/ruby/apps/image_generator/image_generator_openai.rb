class ImageGeneration < MonadicApp
  include OpenAIHelper

  icon = "<i class='fa-regular fa-image'></i>"

  description = <<~TEXT
    This application generates and edits images based on text prompts. It supports creating new images from prompts, editing existing images with optional masks, and generating variations of images. You can customize output options such as number of images, image size, format, quality, background and compression. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=image-generator" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You help the user generate and edit images using OpenAI's gpt-image-1 model.
    1. For new image generation, call generate_image_with_openai({
         operation: "generate",
         model: "gpt-image-1",
         prompt,
         n,
         size,
         quality,
         output_format,
         background,
         output_compression
       }).
    2. For image editing, call generate_image_with_openai({
         operation: "edit",
         model: "gpt-image-1",
         prompt,
         n,
         images,
         mask,
         size,
         quality,
         output_format,
         background,
         output_compression
       }).
       IMPORTANT: When mask images are provided, ALWAYS include the mask parameter in your function call.
       The mask parameter should specify the mask image filename in the shared folder.
    3. For variation, call generate_image_with_openai({
         operation: "variation",
         model: "gpt-image-1",
         n,
         images
       }).
    After receiving a response, embed the returned image URLs using Markdown image syntax WITHOUT placing them in code blocks. For example:
      
      ![Generated Image](/data/FILENAME1.png)
      ![Generated Image](/data/FILENAME2.png)
      
    Do not use HTML `<img>` tags and do not place the Markdown images inside code blocks or triple backticks.
    If an error occurs, return the error message without retrying automatically.
  TEXT

  @settings = {
    group: "OpenAI",
    display_name: "Image Generator",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4.1",
    temperature: 0.0,
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image_generation: true,
    tools: [
      {
        type: "function",
        function: {
          name: "generate_image_with_openai",
          description: "Generate or edit images using OpenAI's gpt-image-1 model.",
          parameters: {
            type: "object",
            properties: {
              operation: { type: "string", enum: ["generate","edit","variation"], description: "Operation type: generate, edit, or variation." },
              model: { type: "string", enum: ["gpt-image-1"], description: "The image model to use (fixed to gpt-image-1)." },
              prompt: { type: "string", description: "Prompt text for generation or editing." },
              images: { type: "array", items: { type: "string" }, description: "Filenames in shared folder for edit or variation." },
              mask: { type: "string", description: "Filename in shared folder for mask image." },
              n: { type: "integer", minimum: 1, description: "Number of images to generate." },
              size: { type: "string", enum: ["1024x1024","1024x1536","1536x1024","auto"], description: "Image size or 'auto'." },
              quality: { type: "string", enum: ["low","medium","high","auto"], description: "Quality level for gpt-image-1." },
              output_format: { type: "string", enum: ["png","jpeg","webp"], description: "Output format for gpt-image-1." },
              background: { type: "string", enum: ["transparent","opaque","auto"], description: "Background option for gpt-image-1." },
              output_compression: { type: "integer", minimum: 0, maximum: 100, description: "Compression level for jpeg/webp." }
            },
            required: ["operation","model","n"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }
end
