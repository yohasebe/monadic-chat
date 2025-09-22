# Message Input

After starting the server and selecting an app and configuring it, click the `Start Session` button to display the following screen.

![](../assets/images/monadic-chat-message-input.png ':size=700')

Enter a message in the text area and click the `Send` button to send the message. To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. The voice is converted to text via Speech-to-Text API and displayed in the text area.

<!-- > 📸 **Screenshot needed**: Message input area showing text area, send button, and role selector -->

?> To chat smoothly with the AI agent using voice input and speech synthesis, it is convenient to turn on `Auto Speech` and `Easy Submit` in the System Settings. These are enabled by default in the [Voice Chat](./basic-apps.md#voice-chat) app.

?> The `Role` selector is used to select the role of the message. Normally, select `User`, but by selecting `Assistant` or `System`, you can add or modify the context of the chat. For more information, see the [FAQ](../faq/faq-user-interface.md).

## Uploading Images :id=uploading-images

Uploading images is supported for providers that expose vision-capable models (e.g., OpenAI, Anthropic Claude, xAI Grok, Google Gemini, Mistral, Perplexity). Consult each provider's documentation for the most up-to-date list of supported models.

?> **Note:** PDF uploads are available only for providers whose APIs natively support document attachments (for example, OpenAI, Anthropic Claude, and Google Gemini at the time of writing). Refer to provider documentation for current availability.

Click `Image` (or `Image/PDF` for models that support PDF) to select an image to attach to the message. Supported image formats include JPG, JPEG, PNG, GIF, and WebP.

<!-- > 📸 **Screenshot needed**: File upload dialog showing image format options -->

![](../assets/images/attach-image.png ':size=400')

After uploading the image, image recognition is performed, and the AI agent provides information about the image according to the text prompt (some models do not support image recognition).

![](../assets/images/monadic-chat-message-with-pics.png ':size=700')

## Uploading PDFs :id=uploading-pdfs

When using a provider that supports PDF uploads (such as OpenAI, Anthropic Claude, or Google Gemini), the `Image/PDF` button allows you to attach PDF files in addition to images. Availability depends on the selected model and provider features.


<!-- ![](../assets/images/monadic-chat-pdf-attachment.png ':size=400') -->

As with images, when you upload a PDF file, the contents of the PDF are recognized, and the AI agent provides information about the PDF according to the text prompt.

![](../assets/images/monadic-chat-chat-about-pdf.png ':size=700')

To continue the conversation about the contents of the PDF in the chat, you need to upload the same PDF file with each message input. Once you upload a PDF during a session, Monadic Chat will send that PDF to the AI agent with each message until the session ends. 

For API usage optimization:
- **Anthropic Claude**: If you have enabled `Prompt Caching` in the System Settings, the PDF will be explicitly cached, significantly reducing API costs
- **OpenAI**: PDFs are automatically cached for 5-10 minutes without any special configuration, reducing API costs for cached portions

To end the conversation about the PDF, click the delete `×` button to clear the PDF.


## Reading Text from Document Files :id=reading-text-from-document-files

Click the `From file` button to select a document file. The contents of the selected file are loaded into the text area. Supported file formats include PDF, Word files (`.docx`), Excel files (`.xlsx`), PowerPoint files (`.pptx`), and various text files (`.txt`, `.md`, `.html`, etc).

![](../assets/images/monadic-chat-extract-from-file.png ':size=400')

## Reading Text from URLs :id=reading-text-from-urls

Click the `From URL` button to enter a URL. The content at that URL is loaded into the text area in Markdown format.

![](../assets/images/monadic-chat-extract-from-url.png ':size=400')

## Speech Input :id=speech-input

?> **Note:** Voice input is supported in Chrome, Edge, and Safari browsers.

To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. After voice input ends, the voice is converted to text via the Speech-to-Text API and displayed in the text area.

![](../assets/images/voice-input-stop.png ':size=400')

After voice input, a `p-value` indicating the confidence of the voice input is displayed. The `p-value` is an indicator of the confidence of the voice input, expressed in the range from 0 to 1. The closer the `p-value` is to 1, the higher the confidence of the voice input.

![](../assets/images/voice-p-value.png ':size=400')

## Speech-to-Text Model Selection :id=speech-to-text-model-selection

You can select the Speech-to-Text (STT) model in the console settings. Monadic Chat exposes the STT models that are available from your configured providers (for example, OpenAI Whisper and newer transcribe-capable models). Refer to the provider documentation for detailed capabilities; Monadic automatically optimizes audio formats for each supported model.


## Text-to-Speech Playback

Monadic Chat offers two ways to play synthesized speech:

### Play Button
Each AI response message includes a `Play` button that allows you to listen to the synthesized speech. Click the `Play` button to start playback, and it will change to a `Stop` button. Click `Stop` to halt the playback. The speech is generated using your selected TTS provider and voice settings.


### Auto Speech
When `Auto Speech` is enabled in the Chat Interaction Controls, AI responses are automatically read aloud as soon as they are received. This feature works seamlessly with all supported TTS providers (OpenAI, ElevenLabs, Gemini, and Web Speech API). Auto Speech is particularly useful for voice conversations when combined with `Easy Submit` for hands-free interaction.
