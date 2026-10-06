# Music Generator

Generate original music tracks — full songs or short instrumental clips — from text descriptions.

Generate music from text descriptions using Google's Lyria. Describe the genre, mood, instrumentation, and tempo you want, and the app produces an audio track that plays directly in the chat and is saved to your `Shared Folder`.

**Key Features:**
-   **Full songs**: The default model (Lyria 3.5) creates tracks of a couple of minutes, with vocals and lyrics when you request them.
-   **Fast instrumental clips**: A 30-second clip model is available for quick instrumental sketches, loops, and background ideas.
-   **Lyrics display**: When a track includes vocals, the generated lyrics are shown alongside the audio player.
-   **Image-to-music (optional)**: Attach an image (up to 10) with your request and its mood, colors, and subject influence the composition — no extra step needed.
-   **ElevenLabs Music (optional)**: When `ELEVENLABS_API_KEY` is set, you can ask for a track to be made with ElevenLabs instead of Lyria, for example "make it with ElevenLabs". It is used only when you name ElevenLabs, never in place of Lyria when Lyria fails, and every result names the service that made it. ElevenLabs tracks accept a length (3 seconds to 10 minutes) and an instrumental-only request, and come without a lyrics display.

**Usage:**
1. Describe the music you want, including genre, mood, instrumentation, and tempo. For a vocal track, include the lyrics or the theme to sing about.
2. Ask for a short or instrumental piece to use the fast 30-second clip model; otherwise the full-song model is used by default.
3. Play the result in the chat or download it from the `Shared Folder`.

?> **Note:** Generated audio is saved in the `Shared Folder` and carries an inaudible SynthID watermark. Requests for specific artists' voices or copyrighted lyrics are declined by the model.

**Example requests:**
- "Create an upbeat lo-fi hip hop instrumental with mellow piano" → fast instrumental clip
- "Write a 2-minute indie folk song about a long road trip, with gentle vocals" → full song with lyrics
- Attach a sunset photo and ask "Turn this scene into a quiet piano piece" → image-inspired instrumental

Music Generator is available with the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability).
