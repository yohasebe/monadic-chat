# Expressive Speech

Internal architecture notes for the Expressive Speech feature: how the four
layers connect, how to add a new TTS provider, and known constraints.

## What it does

Some TTS engines interpret inline markers embedded in the spoken text and
reproduce them as natural audio cues — a pause, a laugh, a whispered aside.
When Expressive Speech is active, the assistant is told (via a system-prompt
addendum) which markers the currently-selected TTS engine understands, so it
can weave them naturally into its replies. The transcript is sanitised before
display so the markers never appear as literal text in the UI.

Activation requires two user-side conditions to both be true:

1. **Auto Speech** is on (the sidebar checkbox `check-auto-speech`).
2. The **Text-to-Speech Provider** dropdown is set to an engine with a
   registered marker vocabulary.

Current tag-aware providers:

| Family key      | Provider dropdown value | Engine variants that actually interpret markers |
|-----------------|-------------------------|--------------------------------------------------|
| `xai`           | `grok`                  | xAI Grok TTS (all 5 voices)                      |
| `elevenlabs-v3` | `elevenlabs-v3`         | **Only** ElevenLabs v3. Flash v2.5 and Multilingual v2 are not tag-aware even though they appear in the same dropdown |
| `gemini`        | `gemini-flash`, `gemini-pro` | Gemini 2.5 Flash/Pro TTS                    |

## Four-layer architecture

```
LLM response text (raw with markers)
    │
    ├──► (1) Backend message assembly         →  TTS API (engine interprets markers)
    │
    └──► WebSocket fragment stream
              │
              └──► (2) MarkdownRenderer.render hook
                      └──► TtsTagSanitizer → clean HTML → DOM (no markers visible)

Chat request (before sending)
    │
    └──► (3) SystemPromptInjector
              ├──► :expressive_speech rule → append marker vocabulary to system prompt
              └──► :plain_voice_enforcement rule → tell LLM NOT to emit markers

Auto Speech + tag-aware provider both true
    │
    └──► (4) updateExpressiveSpeechIndicator → show ✨ badge in UI
```

### Layer 1: TTS text processor registry (backend)

`docker/services/ruby/lib/monadic/utils/tts_text_processors.rb`

Two hash tables keyed by canonical family:

- `PRE_SEND`: text transform applied just before the TTS API call. Currently
  identity for all registered families (xAI/ElevenLabs/Gemini all accept
  markers verbatim). The hook exists for future normalisation needs.
- `DISPLAY_SANITIZE`: regex-based stripper applied before the text reaches
  the DOM. Removes the marker vocabulary while preserving surrounding
  punctuation.

The module also owns `family_for(provider)`, the single normalisation point.
All other layers delegate through it.

### Layer 2: Sanitizer frontend mirror

`docker/services/ruby/public/js/monadic/tts-tag-sanitizer.js`

A byte-for-byte mirror of `DISPLAY_SANITIZE` in JS. Exposed as
`window.TtsTagSanitizer` with `familyFor`, `sanitizeForDisplay`, `tagAware`.

Hooked into `markdown-renderer.js` `render()` entry so every assistant card
— streaming or historical — is sanitised when `params.tts_provider` is tag-aware.

Drift between Ruby and JS is caught by `spec/unit/utils/tts_registry_sync_spec.rb`.

### Layer 3: Marker vocabulary + prompt injection

`docker/services/ruby/lib/monadic/utils/tts_marker_vocabulary.rb`

Data-driven registry: per family, a list of inline markers, optional wrapping
tags, and example phrasings. `prompt_addendum_for(provider)` assembles a
full system-prompt addendum (vocabulary + usage rules + meta-reference
prohibition) from the table.

Wired into `SystemPromptInjector` at priority 30 (positive) and 29 (plain-voice
mirror). Placed at the tail so Anthropic/OpenAI prompt caches keep the stable
prefix hot when the user changes TTS providers mid-session.

### Layer 4: UI indicator

`docker/services/ruby/public/js/monadic.js` — `updateExpressiveSpeechIndicator()`

Reactive to four events: page load, Auto Speech toggle, TTS provider change,
app switch. Reads `check-auto-speech.checked` and the `#tts-provider` select
value directly so state drift is impossible.

Badge: `#expressive-speech-indicator` in `views/index.erb`, styled with Bootstrap
5 subtle palette (`bg-secondary-subtle text-secondary-emphasis border…`) to
match the app's muted aesthetic rather than a vivid status colour.

## Adding a new TTS provider

Suppose Cartesia Sonic 2 ships inline-marker support. Steps:

1. **Decide the family key and what providers normalise to it.**
   Add a branch to `TtsTextProcessors.family_for` (and its JS twin) mapping
   the dropdown value(s) to the new family.

2. **Add the sanitizer regex** to `DISPLAY_SANITIZE` in Ruby AND JS. Keep the
   shape consistent (strip markers → collapse double spaces → fix
   space-before-punctuation). If the engine supports free-form descriptor
   tags (like Gemini), include a bounded lowercase catch-all such as
   `[a-z][a-z ]{2,60}`.

3. **Add a vocabulary entry** to `TtsMarkerVocabulary::VOCABULARIES` with
   inline markers, wrapping markers (or `[].freeze`), and 2–3 example
   phrasings.

4. **Run `npm test` and `rspec spec/unit/utils/tts_*`**. The registry sync
   spec will fail loudly if Ruby and JS marker lists disagree.

5. **Update `docs/basic-usage/basic-apps.md` + ja/**, plus the tooltip in
   `public/js/i18n/translations.js`, to list the new family under "Supported
   by…".

No changes are required in vendor helpers, UI handlers, or the prompt
injector — the four layers all read from the registry.

### Narrowing down to a specific model family

The ElevenLabs case is the cautionary tale: the dropdown lists three variants
(`elevenlabs-flash`, `elevenlabs-multilingual`, `elevenlabs-v3`), but ONLY v3
actually interprets markers. The fix is to give v3 its own family key
(`elevenlabs-v3`) in `family_for`, so the other two fall back to the
unregistered `elevenlabs` family and silently disable Expressive Speech.

Apply the same pattern whenever a brand has a tag-capable flagship model and
legacy variants that would read markers literally.

## Per-app opt-out

Apps with strict output formats (JSON emitters, etc.) can disable the feature
in their MDSL:

```ruby
features do
  expressive_speech false
end
```

The gate lives in `SystemPromptInjector.__expressive_speech_active?`, which
both the `:expressive_speech` and `:plain_voice_enforcement` rules consult.
Setting the flag to `false` skips **both** rules — the app's system prompt
is then untouched by Expressive Speech entirely.

## Known limitations

- **Free-form Gemini tags are not encouraged.** Gemini accepts arbitrary
  descriptive brackets like `[sarcastically, one painfully slow word at a
  time]`, but the prompt vocabulary intentionally lists only the 16 fixed
  tags to keep LLM output predictable. The display regex still strips
  improvised multi-word descriptors so they do not leak into the transcript.
- **Mid-session TTS switch is best-effort.** When the user flips from xAI
  Grok TTS to OpenAI TTS mid-conversation, old assistant turns in the context
  still contain `[laugh]` etc. The `:plain_voice_enforcement` rule counters
  this by explicitly instructing the LLM to ignore previous marker patterns.
  In practice this handles the common case; a small chance remains that the
  LLM still emulates earlier markers for one turn.
- **Streaming briefly shows raw markers.** Fragments arrive as text nodes and
  are visible as literal strings (`[laugh]`) during the streaming window.
  Once the card re-renders through `MarkdownRenderer.render`, the sanitizer
  cleans them up. Users who scrutinise the streaming transition may notice
  the flash; no fix is planned.
- **Prompt cache impact is minimal.** The addendum is at priority 30/29 —
  the tail of the system prompt — so stable prefixes (language, autonomy,
  math, app-specific content) stay cached. Switching TTS providers only
  invalidates the tail.

## Tests at a glance

| Spec | Covers |
|------|--------|
| `spec/unit/utils/tts_text_processors_spec.rb` | Family normalisation, sanitizer regex per family, non-v3 ElevenLabs short-circuit |
| `spec/unit/utils/tts_marker_vocabulary_spec.rb` | Vocabulary data shape, addendum string invariants (meta-reference prohibition, opening-marker ban) |
| `spec/unit/utils/system_prompt_injector_spec.rb` | `:expressive_speech` and `:plain_voice_enforcement` activation matrix, MDSL opt-out, nil-safety |
| `spec/unit/utils/tts_registry_sync_spec.rb` | Ruby constants ≡ JS arrays; family_for parity |
| `test/frontend/tts-tag-sanitizer.test.js` | JS mirror of the sanitizer suite |
