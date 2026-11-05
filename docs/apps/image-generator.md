# Image Generator

Generate and edit images from natural-language descriptions using provider image models.

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

Generate images from text descriptions, and edit images you upload or images generated earlier in the conversation. Image Generator is available with OpenAI, Google Gemini, and xAI (Grok).

With OpenAI, a generated image is shown in the [work screen](../basic-usage/web-interface.md#work-screen), and the reply shows one line with its name. The image stays there while you go on: ask for changes, and the last image in the work screen is edited. **Save to the shared folder** puts an image in the shared folder, and the reply then lists it as saved; an image you have not saved is not in the shared folder. With Google Gemini and xAI (Grok), generated images are saved in the shared folder and shown in the chat.

With OpenAI, image generation is not available in a Private chat.

## Image Editing

To edit an image, describe the changes you want in natural language. If you do not say which image to edit, the latest image you uploaded or the latest generated image in the conversation is used. With OpenAI, it is the last image in the work screen, saved or not. Image editing is supported by OpenAI, Google Gemini, and xAI (Grok).

For example, after generating an image, you can say:
- "Make the sky a sunset orange"
- "Add a cat sitting in the window"
- "Change the sign to read 'Hello World'"

You can also upload an image and give editing instructions for it. Up to 5 images can be attached to a message.

## Options by Provider

- **OpenAI**: choose from several image models. One image is made per request. You can ask for the size, the quality, the output format (PNG, JPEG, or WebP), a transparent background, and the compression level. A mask image can limit an edit to part of the image.
- **Google Gemini**: two models, Flash (fast) and Pro (keeps the look of an uploaded image more closely). When you upload a reference image without choosing a model, the assistant asks which to use. You can ask for an aspect ratio and a resolution (1K, 2K, or 4K), and use several attached images for editing. Flash can also make an image from a video, such as a thumbnail.
- **xAI (Grok)**: you can ask for an aspect ratio and the quality, and use several attached images for editing.

## Image Quality (xAI)

The xAI variant uses its standard image model by default. Ask for higher quality, for example "generate this at higher quality", and it uses the more expensive model for that request. If that model is not available on your account, the image is generated with the standard model, and the reply says so.
