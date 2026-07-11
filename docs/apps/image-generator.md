# Image Generator

Generate and edit images from natural-language descriptions using provider image models.

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

Generate images from text descriptions. Image Generator is available with OpenAI, Google Gemini, and xAI (Grok). With providers that support advanced image workflows, you can perform three main operations:

1.  **Image Generation**: Create new images from text.

2.  **Image Editing**: Modify existing images using text prompts. The system automatically uses images you upload or images generated in the current conversation for editing.

3.  **Image Variation**: Generate alternative versions of an existing image, automatically referencing the latest image in the conversation.

With supported models, the image editing feature allows you to:

- Automatically use an existing image from the conversation as a base (latest uploaded or generated)

- Provide text instructions for the changes (prompt-based editing)

- Customize output options including:

  - Image size and quality

  - Output format (PNG, JPEG, WebP)

  - Background transparency

  - Compression level

## Image Editing

To edit an existing image, simply describe the changes you want in natural language. The model will modify the image based on your prompt while preserving the overall composition. Image editing is supported by OpenAI, Google Gemini, and xAI (Grok).

For example, after generating an image, you can say:
- "Make the sky a sunset orange"
- "Add a cat sitting in the window"
- "Change the sign to read 'Hello World'"

The model interprets your instructions and applies changes to the entire image contextually. You can also upload an image and provide editing instructions to modify it.

All generated images are saved in the `Shared Folder` and also displayed in the chat.
