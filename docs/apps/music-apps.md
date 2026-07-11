# Music Lab & Music Analyst

Two complementary music apps: an interactive lab for learning music theory hands-on, and an analyst that evaluates recorded performances.

## Music Lab :id=music-lab

![Music Lab app icon](../assets/icons/music.png ':size=40')

An interactive lab for learning music theory hands-on: play chords, scales, intervals, and progressions, and generate backing tracks to hear concepts in action. The AI explains music concepts and renders audio examples directly in the browser. To evaluate the musicality and performance of an existing recording, use the Music Analyst app instead.

**Key Features:**
- **Audio/MIDI analysis**: Upload audio files (mp3, wav, m4a, ogg, flac) or MIDI files (mid, midi) to detect tempo, key, time signature, chord progressions, and song structure. MIDI analysis also extracts track/instrument information.
- **Audio playback**: Chords, scales, intervals, and progressions rendered as sheet music with in-browser MIDI synthesis
- **Backing tracks**: Multi-instrument backing tracks (chords + bass) with style-specific patterns (jazz, bossa nova, pop, rock, ballad)
- **Algorithmic melody**: Generate melodies automatically using chord-scale theory, Euclidean rhythms, and contour shaping (lyrical, rhythmic, jazz, latin, gentle styles)
- **Guitar-specific patterns**: Bossa nova arpeggios, rock power chords, ballad fingerpicking
- **Walking bass**: Jazz walking bass with chromatic approach notes, bossa 2-beat feel
- **Comprehensive music theory**: 46 chord types; major, minor, pentatonic, blues, and other scales; all church modes; slash chords; enharmonic spelling

Audio analysis requires the optional **Audio Analysis** package (librosa + madmom) — enable it in **Actions → Install Options** and rebuild the Python container.

Music Lab is available for OpenAI, Claude, Gemini, and Grok.

## Music Analyst :id=music-analyst

![Music Analyst app icon](../assets/icons/music.png ':size=40')

Evaluate a recorded performance from two complementary angles: objective measured features and an interpretive critique of the music and playing. To play, generate, and learn music theory hands-on, use the Music Lab app.

**Key Features:**
- **Objective features**: Extract tempo, key, time signature, chord progression, and song structure from an uploaded audio or MIDI file via signal processing.
- **Interpretive critique**: Gemini listens to the audio and comments on character and mood, genre and instrumentation, and performance qualities (expression, dynamics, phrasing, timing, energy), with strengths, weaknesses, and an overall evaluation.
- **Complementary lenses**: Ask for objective facts, an interpretive critique, or both — the two are presented as clearly separated sections.

The interpretive critique analyzes audio in mono at reduced bandwidth, so it does not judge audio fidelity, mix/mastering, or stereo imaging; exact tempo and key come from the objective feature analysis. Critique applies to real audio (mp3, wav, m4a, ogg, flac); MIDI files use objective analysis only.

Objective feature analysis requires the optional **Audio Analysis** package (librosa + madmom) — enable it in **Actions → Install Options** and rebuild the Python container.

Music Analyst is available for Gemini.
