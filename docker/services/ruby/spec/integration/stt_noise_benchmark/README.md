# STT noise benchmark

Measures how speech-recognition back-ends degrade as noise increases, and —
more importantly — **how** they degrade.

## Why this exists

Monadic Chat lets a user pick among providers for the same task. The project's
position is that **the differences between providers are a feature, not a
selection hurdle**: being able to show that engine A stays faithful where
engine B invents text is part of what a reproducible multi-LLM environment is
for. That makes this harness a standing asset rather than a one-off used to
pick a default and then discarded.

For language teaching in particular, the failure *mode* matters more than the
error *rate*. An engine that drops words under noise leaves a visibly
incomplete transcript. An engine that replaces them with fluent, plausible,
wrong text produces something a learner cannot tell is wrong. Two engines can
post the same WER and be worlds apart on this axis, so every cell in the
report carries the returned word count next to the WER.

## What it measures

Five conditions, applied to the same clean clip:

| condition | noise | SNR |
|---|---|---|
| `clean` | — | — |
| `white_+5dB` | white, seeded | +5 dB |
| `white_0dB` | white, seeded | 0 dB |
| `babble_+5dB` | overlapping speech | +5 dB |
| `babble_0dB` | overlapping speech | 0 dB |

Noise is generated from a seeded PRNG and mixed by measured RMS, so a run on
one machine is byte-identical to a run on another. `corpus_spec.rb` verifies
this by measuring the SNR back out of the mixture at four levels.

## Running it

The measurement calls provider APIs and is billed. It is gated twice:

```bash
cd docker/services/ruby
RUN_API=true RUN_STT_NOISE_BENCH=true bundle exec rspec spec/integration/stt_noise_benchmark/
```

Without both switches the measurement is skipped, while the scoring and mixing
specs still run — those are the parts that have to be correct for any published
number to mean anything, so they are pinned in CI.

Results are written to `tmp/stt_noise_benchmark/<timestamp>/` as `result.json`
(full transcripts) and `result.md` (the table).

### Speech source

By default the clip is synthesised with macOS `say`, pinned to the `Samantha`
voice. To measure human speech instead:

```bash
STT_BENCH_SPEECH_WAV=/path/to/speech.wav RUN_API=true RUN_STT_NOISE_BENCH=true \
  bundle exec rspec spec/integration/stt_noise_benchmark/
```

The WAV must be 16-bit PCM. Update `data/truth.txt` to match what is spoken.

**Trap worth knowing**: `say` uses the system default voice. On a
Japanese-locale machine that is a Japanese voice, so English text comes out
katakana-accented and every engine appears to mis-transcribe it — a corpus bug
that reads exactly like an API bug. The voice is pinned for this reason.

## Engines

| engine | transport | status |
|---|---|---|
| `xai-stt` | REST | ✅ reference line — batch transcriber, stayed accurate in every condition |
| `gpt-4o-mini-transcribe` | REST | ✅ |
| `gpt-realtime-whisper` | WebSocket | ✅ realtime transcription intent |

REST engines go through the application's own `InteractionUtils#stt_api_request`
rather than a private reimplementation, so the benchmark measures the code that
actually ships.

Models are **pinned**, not read from `providerDefaults`. A benchmark whose
subject changes when the product default changes cannot be compared across
months. Add engines rather than editing existing entries.

### Not yet ported

The 2026-07-27 reference run also covered two speech-to-speech engines that are
not in `Engines.default_set` yet. Their verified connection facts, so porting
does not require rediscovering them:

- **Gemini Live** — `wss://generativelanguage.googleapis.com/ws/...BidiGenerateContent?key=`,
  setup frame then `setupComplete`. Rejects `responseModalities: ["TEXT"]`; use
  AUDIO output and read `inputTranscription` only.
- **xAI STS** (`grok-voice-think-fast-2.0`) — `wss://api.x.ai/v1/realtime?model=`.
  **Requires HTTP/1.1**; the upgrade returns 400 over HTTP/2. Note that an
  invalid model name does not error — it silently falls back to 1.0, so
  validate the `model` field in `session.created`.

Two constraints apply to the OpenAI realtime engine and are encoded in
`lib/engines.rb`:

- ALPN must be forced to `http/1.1` (400/405 otherwise).
- Audio must be withheld until `session.updated` arrives; events are processed
  in receive order, so anything appended earlier attaches to the
  not-yet-configured session and the commit comes back empty.
- The GA endpoint rejects the old `openai-beta: realtime=v1` header.

## Reference run (2026-07-27)

WER, lower is better. Synthetic speech, one trial per cell.

| condition | xai-stt (REST) | Grok STS | OpenAI Realtime | Gemini Live |
|---|---|---|---|---|
| clean | 0% | 0% | 0% | 0% |
| white +5dB | 4% | 30% | 4% | 4% |
| white 0dB | 4% | 74% | 0% | 4% |
| babble +5dB | 0% | 43% | 4% | 0% |
| babble 0dB | 0% | 100%※ | 70% | 100%※ |

※ no response within the client timeout, not a wrong answer.

The finding that mattered was not the rates but the shapes:

- **OpenAI** degraded by *omission* — at babble 0dB it returned one sentence,
  and that sentence was correct.
- **Grok STS** degraded by *fabrication* — at babble +5dB it produced fluent
  sentences that were not in the source at all.
- **Gemini** stayed faithful through babble +5dB.

## Limitations

Stated plainly, because they bound what the numbers support:

- Synthetic speech, not human speech. This is the largest caveat.
- One trial per cell; no variance estimate.
- A timeout is a client-side decision. Turn-detection settings on the realtime
  engines can move that boundary, so "no response" is a property of this
  harness's configuration as much as of the engine.
- Conditions are English-only. Japanese listening accuracy is deliberately out
  of scope for now.
