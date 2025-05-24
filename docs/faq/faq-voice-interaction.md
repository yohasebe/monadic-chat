# FAQ: Voice Interaction

**Q**: Sometimes the text is played back in a different language than the actual language during speech synthesis. What should I do?

**A**: The `Speech-to-Text (STT) Language` selector on the web interface is set to `Automatic` by default. By setting it to a specific language, the text will be played back in the specified language during speech synthesis.

---

**Q**: Can I use text-to-speech without an OpenAI or ElevenLabs API key?

**A**: Yes, you can use the Web Speech API option in the Text-to-Speech Provider dropdown. This uses your browser's built-in speech synthesis capabilities and doesn't require any API keys. The available voices will depend on your operating system and browser, but most modern browsers support this feature.

---

**Q**: How do I select voices when using the Web Speech API for text-to-speech?

**A**: After selecting "Web Speech API" as your Text-to-Speech Provider, a dropdown menu will appear showing all available voices on your system. These voices are provided by your operating system and browser. Different operating systems (Windows, macOS, Linux) will have different voice options available.

---

**Q**: Can I adjust the speed of the AI agent's voice?

**A**: Yes, you can adjust the playback speed of the synthesized speech using the `Text-to-Speech Speed` slider in the Speech Settings panel. The speed can be adjusted from 0.7 (slower) to 1.2 (faster). ElevenLabs voices generally provide better quality at modified speeds compared to OpenAI voices. The Web Speech API also supports speed adjustment, though quality may vary.

---

**Q**: What is Gemini TTS and how does it differ from other providers?

**A**: Gemini TTS is Google's text-to-speech service that offers two models: Gemini Flash TTS (faster, uses gemini-2.5-flash-preview-tts) and Gemini Pro TTS (higher quality, uses gemini-2.5-pro-preview-tts). Both models provide 8 unique voices (Aoede, Charon, Fenrir, Kore, Orus, Puck, Schedar, Zephyr) with natural-sounding speech synthesis. Gemini TTS requires a Gemini API key and supports both real-time streaming for interactive conversations and MP3 file generation through the Speech Draft Helper app.

---

**Q**: Can I save the input text as an MP3 file by synthesizing speech?

**A**: Yes, you can save the synthesized speech as a file by selecting the `Speech Draft Helper` app, entering the text, and instructing the AI agent to convert it to an MP3 file. The Speech Draft Helper supports multiple TTS providers including OpenAI, ElevenLabs, and Gemini (using gemini-2.5-flash-preview-tts model), allowing you to choose different voices and providers for MP3 generation.

---

**Q**: Can I have a voice conversation with the AI agent?

**A**: Yes, you can. Enable both `Auto speech` and `Easy submit` in the `Chat Interaction Controls` on the web interface. You can start and complete voice message input by pressing the Enter key (without clicking a button). Also, when the input is complete, the message is automatically sent, and the synthesized voice of the response from the AI agent is played. In other words, you can have a voice conversation with the AI agent just by pressing the Enter key at the right time.

---

**Q**: Which speech-to-text models are available, and how do I select them?

**A**: Monadic Chat supports multiple OpenAI speech-to-text models including 'whisper-1', 'gpt-4o-mini-transcribe', and 'gpt-4o-transcribe'. You can select your preferred model in the settings panel under the STT_MODEL option. The newer models (gpt-4o-mini-transcribe, gpt-4o-transcribe) generally provide improved accuracy and transcription quality. Monadic Chat automatically optimizes the audio format based on which model you select.

