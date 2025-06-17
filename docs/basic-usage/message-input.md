# Message Input

After starting the server and selecting an app and configuring it, click the `Start Session` button to display the following screen.

![](../assets/images/monadic-chat-message-input.png ':size=700')

Enter a message in the text area and click the `Send` button to send the message. To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. The voice is converted to text via Speech-to-Text API and displayed in the text area.

?> To chat smoothly with the AI agent using voice input and speech synthesis, it is convenient to turn on `Auto Speech` and `Easy Submit` in the System Settings. These are enabled by default in the [Voice Chat](./basic-apps.md#voice-chat) app.

?> The `Role` selector is used to select the role of the message. Normally, select `User`, but by selecting `Assistant` or `System`, you can add or modify the context of the chat. For more information, see the [FAQ](../faq/faq-user-interface.md).

## Uploading Images

Uploading images is supported for the following models:

- OpenAI GPT
- Anthropic Claude
- xAI Grok
- Google Gemini
- Mistral AI (Pixtral, Mistral Medium 2505)
- Perplexity AI

Note: PDF uploads are only supported by OpenAI (gpt-4.1, gpt-4o, o1 series), Claude, and Gemini models.

Click `Image` (or `Image/PDF` for models that support PDF) to select an image to attach to the message. Supported image formats include JPG, JPEG, PNG, GIF, and WebP.

![](../assets/images/attach-image.png ':size=400')

After uploading the image, image recognition is performed, and the AI agent provides information about the image according to the text prompt (some models do not support image recognition).

![](../assets/images/monadic-chat-message-with-pics.png ':size=700')

## Uploading PDFs

In Anthropic's Sonnet models, OpenAI's gpt-4.1, gpt-4.1-mini, gpt-4.1-nano, gpt-4o, gpt-4o-mini, and o1 models, and Google Gemini models, PDF uploads are supported in addition to images. Click `Image/PDF` to select a PDF file to attach to the message.

![](../assets/images/monadic-chat-pdf-attachment.png ':size=400')

As with images, when you upload a PDF file, the contents of the PDF are recognized, and the AI agent provides information about the PDF according to the text prompt.

![](../assets/images/monadic-chat-chat-about-pdf.png ':size=700')

To continue the conversation about the contents of the PDF in the chat, you need to upload the same PDF file with each message input. Once you upload a PDF during a session, Monadic Chat will send that PDF to the AI agent with each message until the session ends. If you have enabled `Prompt Caching` in the System Settings, prompts for the same PDF will be cached, saving on API usage. To end the conversation about the PDF, click the delete `×` button to clear the PDF.

## Reading Text from Document Files

Click the `From file` button to select a document file. The contents of the selected file are loaded into the text area. Supported file formats include PDF, Word files (`.docx`), Excel files (`.xlsx`), PowerPoint files (`.pptx`), and various text files (`.txt`, `.md`, `.html`, etc).

![](../assets/images/monadic-chat-extract-from-file.png ':size=400')

## Reading Text from URLs

Click the `From URL` button to enter a URL. The content at that URL is loaded into the text area in Markdown format.

![](../assets/images/monadic-chat-extract-from-url.png ':size=400')

## Speech Input

?> Currently, voice input is supported in Chrome, Edge, and Safari browsers.

To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. After voice input ends, the voice is converted to text via the Speech-to-Text API and displayed in the text area.

![](../assets/images/voice-input-stop.png ':size=400')

After voice input, a `p-value` indicating the confidence of the voice input is displayed. The `p-value` is an indicator of the confidence of the voice input, expressed in the range from 0 to 1. The closer the `p-value` is to 1, the higher the confidence of the voice input.

![](../assets/images/voice-p-value.png ':size=400')

## Speech-to-Text Model Selection

You can select the Speech-to-Text (STT) model in the console settings. Monadic Chat supports the following OpenAI STT models:
- whisper-1
- gpt-4o-mini-transcribe
- gpt-4o-transcribe

The newer models (gpt-4o-mini-transcribe, gpt-4o-transcribe) provide improved accuracy and transcription quality. Monadic Chat automatically optimizes the audio format for each STT model to ensure the best possible transcription results.

## Text-to-Speech Playback

Monadic Chat offers two ways to play synthesized speech:

### Play Button
Each AI response message includes a `Play` button that allows you to listen to the synthesized speech. Click the `Play` button to start playback, and it will change to a `Stop` button. Click `Stop` to halt the playback. The speech is generated using your selected TTS provider and voice settings.

### Auto Speech
When `Auto Speech` is enabled in the Chat Interaction Controls, AI responses are automatically read aloud as soon as they are received. This feature works seamlessly with all supported TTS providers (OpenAI, ElevenLabs, Gemini, and Web Speech API). Auto Speech is particularly useful for voice conversations when combined with `Easy Submit` for hands-free interaction.
