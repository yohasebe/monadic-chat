# Music Tutor & Music Analyst

Two music apps: Music Tutor teaches music theory with explanations, playable scores, and backing patterns, and Music Analyst analyzes audio or MIDI files and gives interpretive feedback on recorded performances. To make new music as an audio file from a text description, use [Music Generator](music-generator.md).

In both apps, put an audio or MIDI file on the [work screen](../basic-usage/web-interface.md#work-screen). The file is kept in the chat's folder, and an audio file can be played there; MIDI files are not played there.

## Music Tutor :id=music-tutor

![Music Tutor app icon](../assets/icons/music.png ':size=40')

Learn music theory hands-on: play chords, scales, intervals, and progressions, and generate backing tracks to hear concepts in action. The AI explains music concepts and writes its examples as scores that play in the browser. To evaluate the musicality and performance of an existing recording, use the Music Analyst app instead.

**Key Features:**
- **Audio/MIDI analysis**: Put audio files (mp3, wav, m4a, aac, wma, ogg, flac) or MIDI files (mid, midi) on the work screen to detect tempo, key, time signature, chord progressions, and song structure. MIDI analysis also extracts track/instrument information.
- **Audio playback**: Chords, scales, intervals, and progressions are shown as sheet music in the [work screen](../basic-usage/web-interface.md#work-screen) beside the chat and played there with in-browser MIDI synthesis, with the instrument sounds of the FluidR3 GM sound font by Frank Wen ([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/us/)), as rendered in [midi-js-soundfonts](https://github.com/paulrosen/midi-js-soundfonts). Each one is a `.abc` file in the chat's folder of the shared folder; the reply names its path
- **Backing tracks**: Multi-instrument backing tracks (chords + bass) with style-specific patterns (jazz, bossa nova, pop, rock, ballad)
- **Algorithmic melody**: Generate melodies automatically using chord-scale theory, Euclidean rhythms, and contour shaping (lyrical, rhythmic, jazz, latin, gentle styles)
- **Guitar-specific patterns**: Bossa nova arpeggios, rock power chords, ballad fingerpicking
- **Walking bass**: Jazz walking bass with chromatic approach notes, bossa 2-beat feel
- **Comprehensive music theory**: 46 chord types; major, minor, pentatonic, blues, and other scales; all church modes; slash chords; enharmonic spelling

Audio and MIDI analysis require the optional **Music Analysis** package (librosa + madmom). Turn it on in **Actions → Install Options** and rebuild the Python container.

Music Tutor is available for OpenAI, Claude, Gemini, and Grok.

## Music Analyst :id=music-analyst

![Music Analyst app icon](../assets/icons/music.png ':size=40')

Evaluate a recorded performance from two complementary angles: features measured from the file and an interpretive critique of the music and playing. To play, generate, and learn music theory hands-on, use the Music Tutor app.

**Key Features:**
- **Measured features**: Estimate tempo, key, time signature, chord progression, and song structure from an audio or MIDI file on the work screen by signal processing.
- **Interpretive critique**: Gemini listens to the audio and comments on character and mood, genre and instrumentation, and performance qualities (expression, dynamics, phrasing, timing, energy), with strengths, weaknesses, and an overall evaluation.
- **Complementary lenses**: Ask for the measured features, an interpretive critique, or both — the two are presented as clearly separated sections.

The interpretive critique analyzes audio in mono at reduced bandwidth, so it does not judge audio fidelity, mix/mastering, or stereo imaging; tempo and key come from the measured features, which are estimates. Critique applies to real audio (mp3, wav, m4a, aac, wma, ogg, flac); MIDI files get the measured features only.

The measured features of audio and MIDI files require the optional **Music Analysis** package (librosa + madmom). Turn it on in **Actions → Install Options** and rebuild the Python container.

Music Analyst is available for Gemini.
