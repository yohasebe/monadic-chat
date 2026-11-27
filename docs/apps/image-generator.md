# Image Generator

Generate and edit images from natural-language descriptions using provider image models.

![Image Generator app icon](../assets/icons/image-generator.png ':size=40')

Generate images from text descriptions, and edit images on the work screen or images generated earlier in the conversation. Image Generator is available with OpenAI, Google Gemini, and xAI (Grok).

A generated image is saved in the chat's folder (`conversations/` in the shared folder) and shown in the [work screen](../basic-usage/web-interface.md#work-screen); the reply shows one line with its path in the shared folder. The image stays in the work screen while you go on: ask for changes, and the last image in the work screen is edited. **Save** under the image in the work screen saves a copy anywhere you choose. If an image's file is changed, moved or deleted in the shared folder, the work screen says so, and that image is no longer shown, edited or saved.


## Image Editing

To edit an image, describe the changes you want in natural language. If you do not say which image to edit, the image your tab shows in the work screen is edited, or else the last image in the work screen. Another image of the work screen you point to, or a file of the shared folder you name in the request (by its name, or by its path such as `conversations/…/artifacts/…png`), is edited instead. Image editing is supported by OpenAI, Google Gemini, and xAI (Grok).

For example, after generating an image, you can say:
- "Make the sky a sunset orange"
- "Add a cat sitting in the window"
- "Change the sign to read 'Hello World'"

To edit an image of your own, put it on the [work screen](../basic-usage/web-interface.md#work-screen) and give editing instructions for it.

To show where and what to change, draw on the image: under the image in the work screen, **Draw on it** makes a whiteboard with the image laid under it (see [Work Screen](../basic-usage/web-interface.md#work-screen)). Mark the place with arrows, circles or words, and ask for the change while the whiteboard is shown: the image and the whiteboard with your drawing are sent together, the drawing as a guide to the change, and the marks are left out of the new image. An earlier image or whiteboard of the work screen is edited when you refer to it; a whiteboard must be shown in your tab. The images of the work screen sent for an edit are kept in the chat's folder (`sent/`) and removed when no message of the chat names them.

## Options by Provider

- **OpenAI**: choose from several image models. One image is made per request. You can ask for the size, the quality, the output format (PNG, JPEG, or WebP), a transparent background, and the compression level.
- **Google Gemini**: two models, Flash (fast) and Pro (keeps the look of a reference image more closely). When you give a reference image without choosing a model, the assistant asks which to use. You can ask for an aspect ratio and a resolution (1K, 2K, or 4K), and name several image files of the shared folder for editing.
- **xAI (Grok)**: you can ask for an aspect ratio and the quality, and use up to 5 images for editing.

## Image Quality (xAI)

The xAI variant uses its standard image model by default. Ask for higher quality, for example "generate this at higher quality", and it uses the more expensive model for that request. If that model is not available on your account, the image is generated with the standard model, and the reply says so.
