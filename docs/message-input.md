# Message Input

After starting the server and selecting an app and configuring it, click the `Start Session` button to display the following screen.

![](./assets/images/monadic-chat-message-input.png ':size=700')

Enter a message in the text area and click the `Send` button to send the message. To use voice input, click the `Voice Input` button to start voice input, and click the `Stop` button to end voice input. The voice is converted to text via the Whisper API and displayed in the text area.

?> To chat smoothly with the AI agent using voice input and speech synthesis, it is convenient to turn on `Auto Speech` and `Easy Submit` in the web settings. These are enabled by default in the [Voice Chat](./basic-apps?id=voice-chat) app.

?> The `Role` selector is used to select the role of the message. Normally, select `User`, but by selecting `Assistant` or `System`, you can add or modify the context of the chat. For more information, see the [FAQ](./faq-user-interface).

# Uploading Images

Click `Upload Image` to select an image to attach to the message.

![](./assets/images/monadi-chat-image-attachment.png ':size=400')

After uploading the image, image recognition is performed, and the AI agent provides information about the image according to the text prompt (some models do not support image recognition).

![](./assets/images/monadic-chat-message-with-pics.png ':size=700')

# Uploading PDFs

In Anthropic's Sonnet model, PDF uploads are supported in addition to images. Click `Upload Image/PDF` to select a PDF file to attach to the message.

![](./assets/images/monadi-chat-pdf-attachment.png ':size=400')

As with images, when you upload a PDF file, the contents of the PDF are recognized, and the AI agent provides information about the PDF according to the text prompt.

![](./assets/images/monadic-chat-chat-about-pdf.png ':size=700')

To continue the conversation about the contents of the PDF in the chat, you need to upload the same PDF file with each message input. Once you upload a PDF during a session, Monadic Chat will send that PDF to the AI agent with each message until the session ends. If you have enabled `Prompt Caching` in the web settings, prompts for the same PDF will be cached, saving on API usage. To end the conversation about the PDF, click the delete `×` button to clear the PDF.
