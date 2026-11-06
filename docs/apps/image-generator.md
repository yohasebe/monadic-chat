# Image Generator

Generate and edit images from natural-language descriptions using provider image models.

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

Generate images from text descriptions, and edit images you upload or images generated earlier in the conversation. Image Generator is available with OpenAI, Google Gemini, and xAI (Grok).

A generated image is saved in the chat's folder (`conversations/` in the shared folder) and shown in the [work screen](../basic-usage/web-interface.md#work-screen); the reply shows one line with its path in the shared folder. The image stays in the work screen while you go on: ask for changes, and the last image in the work screen is edited. **Save as…** (**Download** in a web browser) saves a copy anywhere you choose. If an image's file is changed, moved or deleted in the shared folder, the work screen says so, and that image is no longer shown, edited or saved.

Image generation is not available in a Private chat.

## Image Editing

To edit an image, describe the changes you want in natural language. If you do not say which image to edit, the last image in the work screen is edited. An image you upload with the request, or a file of the shared folder you name in it (by its name, or by its path such as `conversations/…/artifacts/…png`), is edited instead. Image editing is supported by OpenAI, Google Gemini, and xAI (Grok).

For example, after generating an image, you can say:
- "Make the sky a sunset orange"
- "Add a cat sitting in the window"
- "Change the sign to read 'Hello World'"

You can also upload an image and give editing instructions for it. Up to 5 images can be attached to a message.

## Options by Provider

- **OpenAI**: choose from several image models. One image is made per request. You can ask for the size, the quality, the output format (PNG, JPEG, or WebP), a transparent background, and the compression level. A mask image can limit an edit to part of the image.
- **Google Gemini**: two models, Flash (fast) and Pro (keeps the look of an uploaded image more closely). When you upload a reference image without choosing a model, the assistant asks which to use. You can ask for an aspect ratio and a resolution (1K, 2K, or 4K), and use several images for editing.
- **xAI (Grok)**: you can ask for an aspect ratio and the quality, and use up to 5 images for editing.

## Image Quality (xAI)

The xAI variant uses its standard image model by default. Ask for higher quality, for example "generate this at higher quality", and it uses the more expensive model for that request. If that model is not available on your account, the image is generated with the standard model, and the reply says so.
