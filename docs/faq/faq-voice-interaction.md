# FAQ: Voice Interaction

##### Q: Sometimes the text is played back in a different language than the actual language during speech synthesis. What should I do? :id=tts-language-detection

**A**: When **Conversation Language** is set to automatic, the language of the speech is decided from the text, and text that mixes languages can be read in the wrong one. Set **Conversation Language** to the language you use; it is passed to speech synthesis as well as to speech recognition.

---

##### Q: Can I use text-to-speech without an OpenAI or ElevenLabs API key? :id=tts-without-api-key

**A**: Yes. Gemini, Mistral and xAI Grok also offer voices with their own API keys, and without any key you can use the Web Speech API option in the Text-to-Speech Provider dropdown. This uses your browser's built-in speech synthesis capabilities and doesn't require any API keys. The available voices will depend on your operating system and browser, but most modern browsers support this feature.

---

##### Q: How do I select voices when using the Web Speech API for text-to-speech? :id=web-speech-api-voices

**A**: After selecting "Web Speech API" as your Text-to-Speech Provider, a dropdown menu will appear showing all available voices on your system. These voices are provided by your operating system and browser. Different operating systems (Windows, macOS, Linux) will have different voice options available.

---

##### Q: Can I adjust the speed of the AI agent's voice? :id=voice-speed-adjustment

**A**: Yes, you can adjust the playback speed of the synthesized speech using the `TTS Speed` slider in the **Speech** panel. The speed can be adjusted from 0.7 (slower) to 1.2 (faster). The Web Speech API also supports speed adjustment, though quality may vary. With Gemini, the Flash and Flash-Lite options change the speed at playback, so audio files saved with them through the Speech Draft Helper app are at the standard pace; the Pro TTS option is asked for the pace in the request.

---

##### Q: What is Gemini TTS and how does it differ from other providers? :id=gemini-tts-overview

**A**: Gemini TTS is Google's text-to-speech service, offering Flash, Flash-Lite, and Pro TTS options in the provider dropdown of the **Speech** panel. It requires a Gemini API key, and covers both spoken chat responses and audio file generation through the Speech Draft Helper app. The voices and languages on offer are Google's, and change independently of Monadic Chat; the voice dropdown in the **Speech** panel shows what is available.

---

##### Q: Can I save the input text as an audio file by synthesizing speech? :id=saving-audio-files

**A**: Yes, you can save the synthesized speech as a file by selecting the `Speech Draft Helper` app, entering the text, and instructing the AI agent to convert it to an audio file. The Speech Draft Helper supports multiple TTS providers: OpenAI and ElevenLabs output MP3 files, while Gemini outputs WAV files. You can choose different voices and providers for audio generation.

---

##### Q: Can I have a voice conversation with the AI agent? :id=voice-conversation

**A**: Yes, you can. Turn on both `Auto speech` and `Easy submit` in the **Interaction** panel of the web interface. The speech input button then has the focus, so pressing Enter starts and finishes voice input (with Easy Submit on, the Right Arrow key also starts it). When the input finishes, the message is sent automatically, and the response is read aloud. For continuous hands-free conversation, see the Live Conversation app.

---

##### Q: Which speech-to-text models are available, and how do I select them? :id=stt-model-selection

**A**: Monadic Chat supports multiple speech-to-text providers:

- **OpenAI models**: Multiple models with varying accuracy and features. Advanced models support speaker identification (diarization) for multi-person audio.
- **Google Gemini**: Provides advanced audio understanding with flexible language recognition and multilingual support.
- **ElevenLabs Scribe**: High-accuracy speech recognition with word-level timestamps. Requires an ElevenLabs API key.
- **Cohere**: Speech recognition with the Cohere Transcribe model. Requires a Cohere API key.
- **Mistral Voxtral**: Speech recognition with Mistral's Voxtral Transcribe model. Requires a Mistral API key.
- **xAI**: Speech recognition powered by xAI. Requires an xAI API key.

You can select your preferred model in the **Speech** panel under the **Speech-to-Text Model** dropdown. Available models are enabled based on your configured API keys. Your selection is saved in a browser cookie and persists across sessions.

