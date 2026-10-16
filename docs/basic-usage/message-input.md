# Message Input

After starting the server and selecting an app and configuring it, click the `Start Session` button to display the following screen.

<!-- SCREENSHOT: Message input interface showing text area, Send button, Speech Input button, Image/PDF upload button, Text from file button, Text from URL button, and Role selector -->

Enter a message in the text area and click the `Send` button to send it. For voice input, see [Speech Input](#speech-input) below.

?> To chat smoothly with the AI agent using voice input and speech synthesis, turn on `Auto speech` and `Easy submit` in the Interaction panel of the sidebar. They are on by default in the [Voice Chat](../apps/chat-apps.md#voice-chat) app.

?> The `Role` selector sets the role of the message. Normally, select `User`. `User (to add to past messages)` and `Assistant (to add to past messages)` add a message to the conversation without sending it, and `System (to provide additional direction)` adds an instruction. For more information, see the [FAQ](../faq/faq-user-interface.md).

## Uploading Images :id=uploading-images

Image uploads are supported for vision-capable models (OpenAI, Anthropic Claude, xAI Grok, Google Gemini, Mistral, Cohere, DeepSeek, and Ollama vision models).

Click `Image` (or `Image/PDF` for models that support PDF) to select an image. Supported formats: JPG, JPEG, PNG, GIF, WebP. Up to 5 images can be attached to a message.

<!-- SCREENSHOT: File upload dialog showing image format options (JPG, JPEG, PNG, GIF, WebP) -->

After uploading the image, a thumbnail of the uploaded image appears below the message input area with a delete button (×). The image is sent along with your text prompt, and the attachments are cleared once the message is sent.

Attached images are downscaled in the browser before sending (long side up to 2000px, short side up to 768px). For full-resolution analysis of fine details, place the image file in the shared folder instead and ask the AI to analyze it — apps with the image-analysis skill read the original file directly and can be asked to use original fidelity.

<!-- SCREENSHOT: Chat showing user message with attached image thumbnail and AI response analyzing the image content -->

## Uploading PDFs :id=uploading-pdfs

Some providers (OpenAI, Anthropic Claude, Google Gemini) support PDF uploads. Click the `Image/PDF` button to attach a PDF file.

?> **Anthropic Claude**: Claude apps support direct PDF upload for AI content recognition.

<!-- SCREENSHOT: Chat showing user message with attached PDF file indicator and AI response discussing the PDF content -->

The PDF is sent with the message it is attached to, and stays in the conversation history for later turns.

## Uploading Extended Document Formats :id=uploading-extended-documents

Some OpenAI models support an extended set of document formats through the File Inputs API. With such a model, the button reads `Attach file` and accepts the following formats in addition to images and PDFs (up to 50 MB; PDFs up to 35 MB):

- Spreadsheets: `.xlsx`, `.csv`
- Documents: `.docx`, `.pptx`, `.txt`, `.md`
- Data/Markup: `.json`, `.html`, `.xml`

Files are cached per session, so the same document is uploaded to OpenAI only once even if it is referenced across multiple turns.

For models using the Responses API, you can also enter a file URL directly in the modal dialog instead of uploading a local file.

## Attaching Video and Audio Files :id=attaching-video-audio

In apps that analyze video or transcribe audio, the `Image` button also takes video files (MP4, M4V, MOV, WebM, MKV, AVI) or audio files (MP3, M4A, WAV, OGG, Opus, FLAC, AAC, WebM). The file is uploaded to the chat's folder and shown below the message box until you send the message. Video Describer takes videos, and Speech Draft Helper takes audio files.

## Reading Text from Document Files :id=reading-text-from-document-files

Click the `Text from file` button to select a document file. The contents of the selected file are loaded into the text area. Supported file formats include PDF, Word files (`.docx`), Excel files (`.xlsx`), PowerPoint files (`.pptx`), and various text files (`.txt`, `.md`, `.html`, etc).

<!-- SCREENSHOT: File selection dialog allowing user to choose a document file, with extracted text appearing in the message input area -->

## Reading Text from URLs :id=reading-text-from-urls

Click the `Text from URL` button to enter a URL. The content at that URL is loaded into the text area in Markdown format.

<!-- SCREENSHOT: URL input dialog where user enters a web address, with extracted content appearing as Markdown in the message input area -->

## Speech Input :id=speech-input

?> **Note:** Voice input is supported in Chrome, Edge, and Safari browsers.

To use voice input, click the `Speech Input` button to start voice input, and click the `Stop` button to end voice input. Voice input is not available on iPhone and iPad. After voice input ends, the voice is converted to text via the Speech-to-Text API and displayed in the text area.

[Live Conversation](../apps/chat-apps.md#live-conversation) does not use this path: it has neither text input nor a Speech Input button — the microphone streams continuously while the session is open.

<!-- SCREENSHOT: Message input area during voice recording showing animated waveform and Stop button -->

With speech-to-text models that report it, `Last Speech-to-Text p-value` is displayed after voice input: the confidence of the transcription, on a scale from 0 to 1. The closer it is to 1, the more confident the result.

<!-- SCREENSHOT: Message input area showing transcribed text with p-value confidence score displayed below -->

## Speech-to-Text Model Selection :id=speech-to-text-model-selection

Select the Speech-to-Text model in the web UI's Speech panel. Models are available from several providers — see the [Speech Panel](/basic-usage/web-interface.md#speech-settings-panel) for them (each option is enabled when its provider's API key is set).

## Realtime Streaming Transcription :id=realtime-streaming-transcription

A streaming mode is available for the `GPT Realtime Whisper ⚡` entry in the Speech-to-Text Model dropdown. The ⚡ glyph indicates models that emit live partial transcripts during recording. When this model is selected, Speech Input behaves differently from the standard batch path:

- As you speak, a live preview of the accumulated transcript appears in the message text area as **grey text**. The preview updates every few hundred milliseconds.
- You can keep typing in the text area while recording. The grey preview follows your typed cursor — your typed text is never overwritten by partials.
- When you click `Stop`, the final transcript is appended to whatever you had in the text area, and the grey preview clears.
- `Easy submit` sends the message once, with the final transcript only — not with intermediate partials.

<!-- SCREENSHOT: Message input area during realtime streaming — grey italic partial text visible inside the textarea while the user is speaking -->

**When to use streaming vs batch.** Streaming mode gives immediate visual feedback during long utterances and is well-suited for live note-taking or dictation flows. The standard batch path is more cost-efficient for short utterances, and every other model in the dropdown uses it.

**Cost note.** Realtime transcription is billed per audio minute by OpenAI, at a higher rate than its batch transcription. The other models on the dropdown are billed by their own providers; refer to each provider's pricing page for current rates.

**Provider support.** Realtime streaming transcription is available via OpenAI only. Other STT models on the dropdown use the batch path. This transcription feature is separate from the speech-to-speech conversation in [Live Conversation](../apps/chat-apps.md#live-conversation), which is available for OpenAI, xAI, and Gemini.

!> **Privacy Filter interaction.** Audio captured by Speech Input is sent to the provider of the Speech-to-Text model you selected, before any Privacy Filter masking applies. Privacy Filter operates on the **text** sent to the LLM after transcription completes — it does not mask the audio itself. If your audio contains personally identifiable information that you do not want to send to that provider, type the message instead of dictating it.

## Text-to-Speech Playback

**Playback controls**<br />
Click the `Start TTS` icon on any AI response to listen to synthesized speech, and `Stop TTS` to halt playback (hover over the icons to see their names). `Cancel Query` stops the response being written and its speech, including speech still being generated.

**Auto speech**<br />
When `Auto speech` is on in the Interaction panel, AI responses are read aloud automatically. Useful for voice conversations when combined with `Easy submit`.
