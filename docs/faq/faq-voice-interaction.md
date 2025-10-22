# FAQ: Voice Interaction

##### Q: Sometimes the text is played back in a different language than the actual language during speech synthesis. What should I do? :id=tts-language-detection

**A**: The TTS (Text-to-Speech) system automatically detects the language of the text and synthesizes speech accordingly. If the language detection is incorrect, this is usually because the text contains mixed languages or ambiguous content. To ensure correct pronunciation, try to keep your text in a single language. Note that the `Speech-to-Text (STT) Language` setting only affects speech recognition input, not TTS output.

---

##### Q: Can I use text-to-speech without an OpenAI or ElevenLabs API key? :id=tts-without-api-key

**A**: Yes, you can use the Web Speech API option in the Text-to-Speech Provider dropdown. This uses your browser's built-in speech synthesis capabilities and doesn't require any API keys. The available voices will depend on your operating system and browser, but most modern browsers support this feature.

---

##### Q: How do I select voices when using the Web Speech API for text-to-speech? :id=web-speech-api-voices

**A**: After selecting "Web Speech API" as your Text-to-Speech Provider, a dropdown menu will appear showing all available voices on your system. These voices are provided by your operating system and browser. Different operating systems (Windows, macOS, Linux) will have different voice options available.

---

##### Q: Can I adjust the speed of the AI agent's voice? :id=voice-speed-adjustment

**A**: Yes, you can adjust the playback speed of the synthesized speech using the `Text-to-Speech Speed` slider in the Speech Settings panel. The speed can be adjusted from 0.7 (slower) to 1.2 (faster). ElevenLabs voices generally provide better quality at modified speeds compared to OpenAI voices. The Web Speech API also supports speed adjustment, though quality may vary.

---

##### Q: What is Gemini TTS and how does it differ from other providers? :id=gemini-tts-overview

**A**: Gemini TTS is Google's text-to-speech service that uses the gemini-2.5-flash-preview-tts model. It provides 8 unique voices (Aoede, Charon, Fenrir, Kore, Orus, Puck, Schedar, Zephyr) with natural-sounding speech synthesis. Gemini TTS requires a Gemini API key and supports both real-time streaming for interactive conversations and audio file generation through the Speech Draft Helper app (outputs WAV format).

---

##### Q: Can I save the input text as an audio file by synthesizing speech? :id=saving-audio-files

**A**: Yes, you can save the synthesized speech as a file by selecting the `Speech Draft Helper` app, entering the text, and instructing the AI agent to convert it to an audio file. The Speech Draft Helper supports multiple TTS providers: OpenAI and ElevenLabs output MP3 files, while Gemini outputs WAV files. You can choose different voices and providers for audio generation.

---

##### Q: Can I have a voice conversation with the AI agent? :id=voice-conversation

**A**: Yes, you can. Enable both `Auto speech` and `Easy submit` in the `Chat Interaction Controls` on the web interface. You can start and complete voice message input by pressing the Enter key (without clicking a button). Also, when the input is complete, the message is automatically sent, and the synthesized voice of the response from the AI agent is played. In other words, you can have a voice conversation with the AI agent just by pressing the Enter key at the right time.

---

##### Q: Which speech-to-text models are available, and how do I select them? :id=stt-model-selection

**A**: Monadic Chat supports multiple speech-to-text providers:

- **OpenAI models**: 'whisper-1', 'gpt-4o-mini-transcribe', 'gpt-4o-transcribe', and 'gpt-4o-transcribe-diarize'. The newer models generally provide improved accuracy and transcription quality. The diarize model supports speaker identification in multi-person audio, labeling each speaker's contributions.
- **Google Gemini**: 'gemini-2.5-flash' provides advanced audio understanding with flexible language recognition. It supports Japanese spacing normalization (automatically removes morpheme-level spaces for natural Japanese text) and handles multilingual input even when a primary language is specified.

You can select your preferred model in the **Speech Settings** panel under the **Speech-to-Text Model** dropdown. Available models are automatically enabled based on your configured API keys—OpenAI models require an OpenAI API key, and Gemini models require a Gemini API key. Your selection is saved in your browser and persists across sessions. Monadic Chat automatically optimizes the audio format and processing based on which model you select. The language setting acts as a hint for expected language but allows flexible recognition of any spoken language.

