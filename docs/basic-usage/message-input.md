# Message Input

After starting the server and selecting an app and configuring it, click the `Start Session` button to display the following screen.

![](../assets/images/monadic-chat-message-input.png ':size=700')

Enter a message in the text area and click the `Send` button to send the message. To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. The voice is converted to text via Speech-to-Text API and displayed in the text area.

<!-- > 📸 **Screenshot needed**: Message input area showing text area, send button, and role selector -->

?> To chat smoothly with the AI agent using voice input and speech synthesis, it is convenient to turn on `Auto Speech` and `Easy Submit` in the System Settings. These are enabled by default in the [Voice Chat](./basic-apps.md#voice-chat) app.

?> The `Role` selector is used to select the role of the message. Normally, select `User`, but by selecting `Assistant` or `System`, you can add or modify the context of the chat. For more information, see the [FAQ](../faq/faq-user-interface.md).

## Uploading Images :id=uploading-images

Image uploads are supported for vision-capable models (OpenAI, Anthropic Claude, xAI Grok, Google Gemini, Mistral, Perplexity).

Click `Image` (or `Image/PDF` for models that support PDF) to select an image. Supported formats: JPG, JPEG, PNG, GIF, WebP.

<!-- > 📸 **Screenshot needed**: File upload dialog showing image format options -->

![](../assets/images/attach-image.png ':size=400')

After uploading the image, image recognition is performed, and the AI agent provides information about the image according to the text prompt (some models do not support image recognition).

![](../assets/images/monadic-chat-message-with-pics.png ':size=700')

## Uploading PDFs :id=uploading-pdfs

Some providers (OpenAI, Anthropic Claude, Google Gemini) support PDF uploads. Click the `Image/PDF` button to attach a PDF file.

?> **Anthropic Claude**: Claude apps support direct PDF upload for AI content recognition.

![](../assets/images/monadic-chat-chat-about-pdf.png ':size=700')

Once uploaded, the PDF is sent with each message until you click the delete `×` button. Enable `Prompt Caching` in System Settings to reduce API costs when repeatedly referencing the same PDF.


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

Select the Speech-to-Text model in the console settings. Available models include OpenAI and Gemini options.

## Text-to-Speech Playback

**Play Button**<br />
Click the `Play` button on any AI response to listen to synthesized speech. Click `Stop` to halt playback.

**Auto Speech**<br />
When enabled in Chat Interaction Controls, AI responses are automatically read aloud. Useful for voice conversations when combined with `Easy Submit`.

## Provider-Specific Features

### OpenAI Predicted Outputs

?> **OpenAI**: OpenAI apps support Predicted Outputs using the `__DATA__` separator in prompts to distinguish instructions from data to be processed. This speeds up responses and reduces token usage ([Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)).
