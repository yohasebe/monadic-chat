# Expressive Speech — Instruction-Meta Mode (OpenAI TTS)

Implementation design doc for extending Expressive Speech to OpenAI
`gpt-4o-mini-tts`. This is the companion to `docs_dev/expressive_speech.md`
(which covers the inline-marker families xAI / ElevenLabs v3 / Gemini and
the hybrid Gemini mode); read that first.

Status: **shipped in beta.12** (2026-04-22). The design below matches the
implementation. Gemini also became instruction-capable in the same release
as a hybrid variant — see `docs_dev/expressive_speech.md` §"Hybrid mode —
Gemini" for Gemini-specific notes; this document continues to focus on the
OpenAI out-of-band path.

## 1. Problem statement

OpenAI's `gpt-4o-mini-tts` exposes an `instructions` parameter
(natural-language directive: tone, pacing, emotion, pronunciation, pauses)
separate from the spoken text. This is architecturally opposite to the
inline-marker approach: directives travel **out-of-band** instead of embedded
in the text.

The existing Expressive Speech feature handles inline markers only. Extending
it to OpenAI requires a second operating mode ("instruction-meta") that
co-exists with the current inline-marker mode.

## 2. Scope

**In scope:**
- New TTS family `openai-instruction` dispatched from `openai-tts-4o`
- Structured-output contract so the LLM emits `{ message, tts_instructions }`
- Plumbing to route `tts_instructions` from LLM response to
  `tts_api_request(..., instructions:)`
- UI indicator variant
- Per-model metadata in `model_spec.js`
- Fallback chain when structured output fails

**Out of scope:**
- Converting non-Monadic apps to full Monadic mode (see §6)
- Per-sentence instructions (only one instruction per response — confirmed
  by user 2026-04-21)
- Supporting `tts-1` / `tts-1-hd` for instruction mode (they do not accept
  the parameter — they fall back to plain TTS)
- gpt-4o-audio-preview path via chat-completions (different API surface —
  not addressed here)

## 3. Pre-existing infrastructure

The following wiring is already present and reused as-is:

| Layer | File | Status |
|---|---|---|
| TTS HTTP request with `instructions` | `utils/tts_utils.rb:95-97` | ✅ already forwards to `/v1/audio/speech` |
| `text_to_speech` adapter | `adapters/text_to_speech_helper.rb:7` | ✅ accepts `instructions: ""` |
| Tool-level examples | Speech Draft Helper, AutoForge | ✅ already call with instructions |
| Monadic unit/unwrap/bind | `app_extensions.rb`, `json_handler.rb` | ✅ structured JSON parsing helpers exist |
| SystemPromptInjector | `utils/system_prompt_injector.rb` | ✅ rule-based, priority 30/29 slots taken by marker flavour |
| Family dispatch | `utils/tts_text_processors.rb:30` | ✅ `family_for()` — add one branch |
| Marker vocabulary registry | `utils/tts_marker_vocabulary.rb` | ✅ add one vocabulary entry |
| Prompt addendum assembler | `utils/tts_marker_vocabulary.rb:prompt_addendum_for` | ✅ extend to handle instruction-meta shape |
| UI indicator | `updateExpressiveSpeechIndicator` in `monadic.js` | ✅ reactive to 4 events |

**Key implication:** most "new" work is prompt engineering + response parsing,
not API plumbing.

## 4. Family taxonomy extension

Current families:

| Family | Providers (dropdown values) | Mechanism |
|---|---|---|
| `xai` | `grok` | inline markers + wrap tags |
| `elevenlabs-v3` | `elevenlabs-v3` | inline markers |
| `elevenlabs` | `elevenlabs-flash`, `elevenlabs-multilingual` | **inactive** (silent no-op) |
| `gemini` | `gemini-flash`, `gemini-pro` | inline markers |
| `openai` | `openai-tts`, `openai-tts-hd` | **inactive** (plain) |
| `mistral` | `mistral-*`, `voxtral-*` | **inactive** (plain) |

**New family:**

| Family | Providers | Mechanism |
|---|---|---|
| `openai-instruction` | `openai-tts-4o` | out-of-band `instructions` parameter (LLM emits via structured output) |

Dispatch change in `TtsTextProcessors.family_for`:

```ruby
def family_for(provider)
  key = provider.to_s.downcase
  return "xai" if key == "grok" || key.start_with?("xai")
  return "elevenlabs-v3" if key == "elevenlabs-v3" || key == "eleven_v3"
  return "elevenlabs" if key.start_with?("elevenlabs") || key.start_with?("eleven_")
  return "gemini"     if key.start_with?("gemini")
  return "mistral"    if key.start_with?("mistral") || key.include?("voxtral")
  # NEW: isolate the 4o-mini-tts model as its own family
  return "openai-instruction" if key == "openai-tts-4o"
  return "openai"     if key.start_with?("openai") || key.start_with?("tts-")
  key
end
```

Rationale for branching **before** the generic `openai` fallback: only
`gpt-4o-mini-tts` supports `instructions`; `tts-1`/`tts-1-hd` must stay
in the plain `openai` family.

JS mirror in `public/js/monadic/tts-tag-sanitizer.js` gets the same branch.
Registry sync spec (`spec/unit/utils/tts_registry_sync_spec.rb`) enforces
the Ruby/JS match.

## 5. LLM output contract

### 5.1 Two encodings, one concept — by app type

Instruction mode uses **two distinct encodings** depending on whether the
app is declared Monadic in its MDSL. Both carry the same conceptual payload
(user-facing `message` + out-of-band `tts_instructions`); the difference is
in how the payload rides alongside existing app semantics.

**Why two encodings?** Forcing a single encoding (JSON for everything, or
sentinel for everything) was considered and rejected. Analysis is recorded
in §5.4 ("Encoding choice rationale"). Short version: each app type already
has an established output contract, and respecting that contract avoids
runtime-invariant flips and preserves the streaming UX users expect.

### 5.2 Monadic-app encoding (JSON, sibling key)

For apps declared `monadic: true` in MDSL:

```json
{
  "message": "<plain user-facing response text, no inline markers>",
  "context": { ... app-specific fields ... },
  "tts_instructions": "Voice: ...\nTone: ...\nPacing: ...\nEmotion: ...\nPronunciation: ...\nPauses: ..."
}
```

- `tts_instructions` sits as a **sibling of `message`**, not nested in
  `context` — avoids schema collision with per-app `context` shapes
- The per-app `context` field continues to work independently
- `monadic_unwrap` already reads only `message`/`context`; the extra key
  is ignored by existing logic
- Display: `renderMonadicJson` extracts `message` for markdown rendering;
  `tts_instructions` is added to the suppressed-keys list so it never
  surfaces in the JSON section display

### 5.3 Non-Monadic-app encoding (sentinel prefix + plain text)

For apps NOT declared `monadic: true`:

```
<<TTS:Voice: ...
Tone: ...
Pacing: ...
Emotion: ...
Pronunciation: ...
Pauses: ...>>

<plain user-facing response text, standard markdown>
```

- `<<TTS:...>>` sentinel block at the very start of the response
- Closing `>>` terminates the sentinel
- Everything after `>>` (optionally a single leading newline) is the
  user-facing `message` text in plain markdown
- **Backend strips the sentinel before forwarding stream fragments to the
  frontend** — the UI never sees the sentinel, streaming UX is unchanged
- History stores only the stripped message; next-turn LLM sees clean
  prior-turn text

Rationale for this specific sentinel shape:
- `<<...>>` is extremely unlikely to appear in normal markdown (triple
  angle-bracket patterns are not standard), so the delimiter is safe
- The multi-line block inside matches the Monadic JSON field format so
  the LLM's instruction-writing prompt (§5.5) is identical regardless of
  encoding
- The sentinel appearing at the start means the backend buffer can detect
  and strip it in a single regex pass after the first fragment or two
  arrive (no streaming-aware JSON parser needed)

### 5.4 Encoding choice rationale (for reference)

The decision to use two encodings rather than one was made after surveying
the downstream impact. Summary:

| Option | Pros | Cons | Why not |
|---|---|---|---|
| JSON for all apps | Unified display path; deterministic parsing | Non-Monadic apps need runtime JSON mode; tool-calling + `response_format: json_object` conflicts on some providers; raw JSON flashes during streaming; app authors lose their chosen contract | Runtime invariant flip + streaming UX regression |
| Sentinel for all apps | Simple; backend-strippable | Incompatible with Monadic apps' strict JSON `response_format`; would require sentinel inside JSON (ugly) | Breaks existing Monadic-mode schema semantics |
| Hybrid (chosen) | Respects each app type's output contract; streaming UX unchanged; no runtime mode flips | Two parsers + two prompt variants (but both are small) | — |

This trade-off was explicitly chosen during the 2026-04-21 design review
with the priority "works as expected + clean/maintainable". See the
discussion notes in the memory file `openai-tts-instructions-research-
2026-04-21.md` for fuller context.

### 5.5 System prompt addendum — two variants

The `:expressive_speech` rule in `SystemPromptInjector` (priority 30)
produces one of two addenda based on app Monadic state × TTS family. The
**instruction payload body is identical** in both variants (same six-line
Voice/Tone/Pacing/Emotion/Pronunciation/Pauses structure); only the
wrapper differs.

#### Variant A — Monadic-app JSON wrapper

Appended to the addendum of an app that already has `monadic: true`:

```
Expressive Speech (instruction mode): your JSON response should include
an additional top-level field `tts_instructions` alongside `message` and
`context`. The value is a 3-6 line directive for the text-to-speech engine
using this exact attribute structure (one per line):

  Voice: <character of the voice — e.g., warm and clear>
  Tone: <emotional coloring — e.g., sincere, playful>
  Pacing: <speed and rhythm — e.g., steady, rapid>
  Emotion: <state being conveyed>
  Pronunciation: <articulation style>
  Pauses: <where to break>

Keep `tts_instructions` under 600 characters. Match the mood to the
`message` content. If the content is neutral, keep directives neutral
("Voice: natural, balanced. Tone: conversational. Pacing: steady.").

Plain prose only in `message` — no bracketed stage directions like
[laugh] or [pause], no angle-bracket tags like <whisper>.

Example:
{
  "message": "I'm very sorry about the mix-up. Let me sort that out for you right away.",
  "context": { ... your app's usual context fields ... },
  "tts_instructions": "Voice: warm, reassuring.\nTone: sincere, empathetic.\nPacing: steady, unhurried.\nEmotion: genuine concern.\nPronunciation: clear on 'very sorry'.\nPauses: brief after the apology."
}
```

#### Variant B — Non-Monadic-app sentinel prefix

Appended to the addendum of an app without `monadic: true`:

```
Expressive Speech (instruction mode): begin every response with a
text-to-speech directive block, then the actual reply on the next line.

The directive block uses the literal delimiters <<TTS: and >> around a
3-6 line instruction set, one attribute per line:

  <<TTS:Voice: <character of the voice — e.g., warm and clear>
  Tone: <emotional coloring — e.g., sincere, playful>
  Pacing: <speed and rhythm — e.g., steady, rapid>
  Emotion: <state being conveyed>
  Pronunciation: <articulation style>
  Pauses: <where to break>>>

  <the actual user-facing reply begins here in plain markdown>

Keep the directive block under 600 characters. The delimiters <<TTS:
and >> are stripped before the message is shown to the user; only the
reply text after >> is displayed and spoken aloud. Match the mood to
the reply content. Never refer to the delimiters in your reply.

Plain prose only in the reply — no bracketed stage directions like
[laugh] or [pause], no angle-bracket tags like <whisper>.

Example:
<<TTS:Voice: warm, reassuring.
Tone: sincere, empathetic.
Pacing: steady, unhurried.
Emotion: genuine concern.
Pronunciation: clear on 'very sorry'.
Pauses: brief after the apology.>>

I'm very sorry about the mix-up. Let me sort that out for you right away.
```

### 5.6 Rule registration

**Extend the existing `:expressive_speech` rule** (priority 30) rather than
adding a parallel rule. The feature is conceptually one — "Expressive
Speech" — and dispatch by TTS family × app-Monadic state is an internal
detail. One rule means the `features { expressive_speech false }` MDSL
opt-out continues to work without modification, and the "auto_speech on
+ not opted out" gate is not duplicated.

The generator dispatches on family:
- `xai` / `elevenlabs-v3` / `gemini` → marker-vocabulary addendum (existing)
- `openai-instruction` + app is Monadic → Variant A (JSON wrapper)
- `openai-instruction` + app is non-Monadic → Variant B (sentinel prefix)
- others → rule's condition returns false, no injection

### 5.7 Plain-voice-enforcement interaction

The existing `:plain_voice_enforcement` rule (priority 29) tells the LLM
"emit plain prose, no markers". When `openai-instruction` is active, that
directive partially conflicts with "emit a Voice/Tone/... directive block"
from §5.5, because the LLM could interpret "plain prose only" as "no
prefix blocks allowed either".

**Resolution**: `:plain_voice_enforcement` is **skipped** for the
`openai-instruction` family. The instruction-mode addendum already says
"plain prose only in message/reply" as its own directive, so the belt-
and-braces layer is redundant AND potentially contradictory. Two rules
giving overlapping-but-differently-worded instructions is harder for the
LLM to reconcile than one coherent directive.

Condition update in `:plain_voice_enforcement`:
```ruby
condition: ->(session, _options) {
  next false unless Monadic::Utils::SystemPromptInjector.__expressive_speech_active?(session)
  params = session[:parameters] || {}
  tts_provider = params["tts_provider"] || params[:tts_provider]
  tts_provider && !tts_provider.to_s.empty? &&
    !Monadic::Utils::TtsMarkerVocabulary.tag_aware?(tts_provider) &&
    !Monadic::Utils::TtsMarkerVocabulary.instruction_mode?(tts_provider)  # NEW
}
```

### 5.5 Plain voice enforcement interaction

The existing `plain_voice_enforcement` rule (priority 29) instructs the LLM
to NOT emit markers when a non-marker TTS provider is active. For
`openai-instruction` this is still partially needed — markers in the
`message` field would leak. Two options:

1. Keep `plain_voice_enforcement` armed for `openai-instruction` family too
   (conservative).
2. Rely on the instruction-mode contract's "Plain prose only" directive to
   carry that load.

Recommendation: **(1)**. Belt-and-braces; two reinforcing directives are
cheap and the LLM is more reliable about plain text when told explicitly.

## 6. Structured output engagement

**Only Monadic apps engage structured-output (JSON mode).** Non-Monadic
apps keep their existing response contract (plain text streaming); the
sentinel prefix rides inside that plain text, no `response_format` change
needed on the vendor side.

### 6.1 Monadic-app path (JSON)

For apps with `monadic: true`, structured output is already active via the
existing Monadic-mode code in each vendor helper. The addendum in §5.5
Variant A just tells the LLM to include an additional `tts_instructions`
field in the response JSON — no adapter-level changes required. The
existing JSON parsing (per vendor) already emits a Ruby Hash from which we
read `message`, `context`, and (new) `tts_instructions`.

### 6.2 Non-Monadic-app path (sentinel)

For apps without `monadic: true`, no structured-output engagement at all.
The LLM emits plain text prefixed with `<<TTS:...>>`. The sentinel is
stripped server-side (§7) before any storage or downstream use.

This means **tool-using non-Monadic apps retain full tool-calling
capability** — there's no `response_format: json_object` to conflict with
function calling on providers that have that limitation.

### 6.3 Cross-provider LLM × TTS mix

Example: user selects **xAI Grok** (LLM) + **OpenAI TTS 4o** (TTS) on a
**non-Monadic** app (Voice Chat).

- System prompt addendum injected into Grok's system message (Variant B,
  sentinel-prefix directive)
- Grok emits plain text: `<<TTS:Voice:...>>\n\nHello, how can I help?`
- Backend streaming handler strips sentinel, forwards clean fragments
- At post-completion TTS: clean message → TTS `input`; extracted
  instructions → TTS `instructions` parameter on OpenAI API
- Frontend display: unchanged, markdown render of clean message

Works because LLM vendor and TTS vendor are decoupled in the existing
code. No new cross-vendor abstractions needed.

## 7. Response parsing

New module `utils/tts_instruction_extractor.rb` with two entry points
matching the two encodings. Both return a `[message, instructions_or_nil]`
tuple; callers don't need to know which encoding was used.

### 7.1 Sentinel extractor (non-Monadic apps)

```ruby
module Monadic
  module Utils
    module TtsInstructionExtractor
      # Sentinel starts at absolute beginning of the text (after optional
      # whitespace). We use a multi-line-aware regex with non-greedy body.
      SENTINEL_RE = /\A\s*<<TTS:(.*?)>>\s*/m

      # Returns [clean_message, instructions_or_nil].
      # Safe on any input — returns [input, nil] when sentinel absent.
      def self.extract_sentinel(text)
        return [text, nil] if text.nil? || text.empty?
        m = text.match(SENTINEL_RE)
        return [text, nil] unless m
        instructions = m[1].to_s.strip
        instructions = nil if instructions.empty?
        cleaned = text.sub(SENTINEL_RE, '')
        [cleaned, instructions]
      end
    end
  end
end
```

### 7.2 JSON extractor (Monadic apps)

```ruby
def self.extract_json(text)
  return [text, nil] if text.nil? || text.empty?
  begin
    parsed = JSON.parse(text)
    return [text, nil] unless parsed.is_a?(Hash)
    return [text, nil] unless parsed["message"].is_a?(String)
    instructions = parsed["tts_instructions"]
    instructions = nil unless instructions.is_a?(String) && !instructions.empty?
    # Don't reshape the JSON — downstream Monadic display still wants the
    # full structure. Just return the message text and instructions. The
    # `tts_instructions` key is suppressed at display time (§8.2).
    [parsed["message"], instructions]
  rescue JSON::ParserError
    [text, nil]
  end
end
```

### 7.3 Dispatcher

```ruby
# Pick the right extractor by app-Monadic state.
def self.extract(text, app_is_monadic:)
  app_is_monadic ? extract_json(text) : extract_sentinel(text)
end
```

Called from two places in `streaming_handler.rb`:

1. **During streaming** (sentinel path only): strip sentinel from the
   buffer before forwarding each fragment. Once the closing `>>` is found
   in the running buffer, everything up to and including it is discarded;
   subsequent fragments pass through unchanged. See §7.4.
2. **At post-completion** (both paths): extract the final `[message,
   instructions]` tuple from `buffer.join` and pass both to
   `start_tts_playback(..., instructions: instructions)`.

### 7.4 Streaming-safe sentinel stripping

Non-Monadic streaming needs to hide the sentinel from the user even
during mid-stream. Approach:

```
state = :looking_for_sentinel
buffer = ""

on fragment(text):
  if state == :looking_for_sentinel
    buffer << text
    if buffer.match?(/\A\s*<<TTS:/)
      # Definitely in sentinel. Wait for closing >>.
      if m = buffer.match(/\A\s*<<TTS:.*?>>\s*/m)
        # Complete sentinel found; strip and forward the remainder.
        state = :passthrough
        after = buffer.sub(m[0], '')
        forward_to_frontend(after) unless after.empty?
        instructions_for_this_turn = m[1].strip  # save for post-completion TTS
        buffer.clear
      # else: sentinel not yet closed, continue buffering (no forward)
      end
    else
      # Sentinel NOT at start → no sentinel this turn. Forward what we buffered.
      state = :passthrough
      forward_to_frontend(buffer)
      buffer.clear
    end
  else  # :passthrough
    forward_to_frontend(text)
  end
```

The "is sentinel starting?" detection happens as soon as we have enough
characters to match `<<TTS:` (6 chars). Worst-case buffering is the first
fragment or two — streaming latency impact is negligible.

For post-completion TTS the full-buffer extractor (§7.1) runs again on
`buffer.join` — this is the one source of truth even if the streaming
sentinel-stripping layer missed (defence in depth).

## 8. TTS call integration + display hygiene

### 8.1 TTS call integration

`tts_api_request` already accepts `instructions:` and forwards it to
OpenAI's `/v1/audio/speech` (see `utils/tts_utils.rb:95-97`). The call
chain `start_tts_playback` → `start_single_tts_request` → `tts_api_request`
gains one new keyword argument threaded through all three methods.

`streaming_handler.rb` is the source — it already calls `start_tts_playback`
at post-completion. Before that call, run the extractor (§7.1/§7.2) on
`buffer.join` (or `tts_text_from_target` when set), then pass the result:

```ruby
text = tts_text_from_target || buffer.join
tts_instructions = nil

if instruction_mode_active?(tts_provider)
  text, tts_instructions = Monadic::Utils::TtsInstructionExtractor.extract(
    text,
    app_is_monadic: monadic_enabled?(app_obj)
  )
end

start_tts_playback(
  text: text,
  provider: provider,
  voice: voice,
  speed: speed,
  response_format: response_format,
  language: language,
  instructions: tts_instructions,  # NEW
  ws_session_id: ws_session_id
)
```

`tts_api_request` already branches `if instructions` so nil is safe.

### 8.2 Display hygiene — suppressing `tts_instructions`

For Monadic apps in instruction mode, the final JSON response still
includes `tts_instructions`. `renderMonadicJson` (frontend,
`markdown-renderer.js:414`) and its Ruby twin (`html_renderer.rb`'s
`json_to_html`) both iterate over top-level keys and render each as a
"JSON section" under the message. Without action, `tts_instructions`
would render as a visible section titled "Tts Instructions".

Fix: add a small **suppressed-keys set** in both the JS and Ruby renderers
that skips designated keys. Initially just `tts_instructions`; future
keys (if ever) can be added to the same list.

```javascript
// markdown-renderer.js, inside jsonToHtml or renderField
const SUPPRESSED_KEYS = new Set(["tts_instructions"]);
// ... skip rendering when key ∈ SUPPRESSED_KEYS
```

```ruby
# html_renderer.rb (or equivalent Ruby rendering path)
SUPPRESSED_KEYS = %w[tts_instructions].freeze
# ... skip when key ∈ SUPPRESSED_KEYS
```

This keeps `tts_instructions` internal-only: it rides in the JSON over the
wire, reaches the renderer, and is quietly dropped from the UI.

### 8.3 Session history hygiene — strip before replay

After extraction, the **clean message** is what gets stored in
`session[:messages]` for the next-turn LLM context. Two cases:

1. **Sentinel (non-Monadic)**: sentinel-stripped plain text is stored.
   Next turn, the LLM sees no prior sentinel → cleanest behaviour.
2. **JSON (Monadic)**: the full JSON is normally stored (existing Monadic
   behaviour). We additionally strip `tts_instructions` from the stored
   JSON before history serialisation. The `context` field (per-app state)
   is preserved as before.

Strip logic for the JSON path runs once at the history-write site after
vendor helpers assemble the assistant message. One central function in
`utils/tts_instruction_extractor.rb`:

```ruby
def self.strip_from_history_json(json_text)
  return json_text unless json_text.is_a?(String)
  begin
    parsed = JSON.parse(json_text)
    return json_text unless parsed.is_a?(Hash) && parsed.key?("tts_instructions")
    parsed.delete("tts_instructions")
    parsed.to_json
  rescue JSON::ParserError
    json_text
  end
end
```

Called from the vendor helpers' history-append path. For vendor helpers
that already serialise the assistant JSON, this is a one-line insertion.

## 9. model_spec.js metadata

Add per-TTS-model metadata (new keys, backward-compatible):

```javascript
"gpt-4o-mini-tts-2025-12-15": {
  tts_capability: true,
  tts_family: "openai-instruction",
  tts_instructions_capability: true,
  tts_voices: ["alloy","ash","ballad","coral","echo","fable","onyx",
               "nova","sage","shimmer","verse","marin","cedar"],
  tts_default_voice: "coral",
  tts_max_input_tokens: 2000,
  tts_audio_formats: ["mp3","opus","aac","flac","wav","pcm"],
  tts_streaming: true,
  // ...existing keys
},
"gpt-4o-mini-tts-2025-03-20": {
  // identical but pinned snapshot — reliability fallback
  tts_instructions_reliability_preferred: true,
  // ...
},
"tts-1-hd": {
  tts_capability: true,
  tts_family: "openai",         // plain
  tts_instructions_capability: false,
  tts_voices: ["alloy","ash","coral","echo","fable","onyx","nova","sage","shimmer"],
  // ...
},
"tts-1": { /* same shape as tts-1-hd */ },
"grok-tts": {
  tts_family: "xai",
  tts_instructions_capability: false,
  // ...
},
```

Ruby-side accessor in `utils/model_spec.rb` (pattern established by existing
`ModelSpec` helpers):

```ruby
def self.tts_family(model_name)
  spec = lookup(model_name)
  spec && spec["tts_family"]
end

def self.tts_instructions?(model_name)
  !!lookup(model_name)&.[]("tts_instructions_capability")
end
```

## 10. UI indicator

`updateExpressiveSpeechIndicator()` in `monadic.js` currently shows a single
✨ badge when inline-marker mode is active. Extend to show mode variant:

```javascript
const family = window.TtsTagSanitizer.familyFor(ttsProvider);
const badge = $id("expressive-speech-indicator");

if (!autoSpeech || !expressiveSpeechSupported) {
  $hide(badge);
  return;
}

if (family === "openai-instruction") {
  badge.textContent = "✨ Expressive Speech (instructions)";
  $show(badge);
} else if (["xai","elevenlabs-v3","gemini"].includes(family)) {
  badge.textContent = "✨ Expressive Speech (markers)";
  $show(badge);
} else {
  $hide(badge);
}
```

Tooltip copy updated accordingly in `translations.js` (EN + JA).

## 11. Fallback chain

Two layers — deliberately kept minimal. The "always-works" guarantee lives
in L2; anything more (e.g., session-level auto-disable) was considered and
rejected as unnecessary state that doesn't change observable behaviour.

**L1 — Structured output success (happy path)**

LLM returns valid JSON with both `message` and `tts_instructions`.
Both parts flow to their destinations. This is the expected case for
all vendors with reliable JSON mode (OpenAI, Anthropic, Gemini, xAI-compat,
DeepSeek, Mistral, Cohere).

**L2 — Parse failure → plain TTS**

`extract_instruction_mode_payload` returns `[raw_text, nil]`. The raw LLM
output is spoken as-is (without instructions), and the card displays the
raw output. User still hears the response; they just miss the expressive
styling for that turn. No error surfaces in UI.

Triggers:
- Small Ollama models that can't hold JSON format
- LLM produces text prose instead of JSON (ignoring system prompt)
- Response is valid JSON but missing `message` field

Logged at `EXTRA_LOGGING=true`: `[ExpressiveSpeech] instruction-mode parse
failed, falling back to plain TTS`.

**Why no L3**: a per-session auto-disable after N consecutive failures was
considered but rejected. It would add a session flag, a reset path (toggle
Auto Speech off/on), and a counter — extra state without a real behavioural
improvement, because L2 already gives the correct outcome on every failed
turn. The only thing L3 would do is stop retrying the structured-output
prompt after N failures; in practice this saves a negligible amount of
tokens and complicates the code. Keep it simple.

## 12. Decided details (formerly open questions)

These were candidates for deferred decision; they are now locked as the
design chose "works as expected + clean architecture" as the tie-breaker.

1. **Snapshot pin policy — use `providerDefaults[0]`, no special env var**

   The OpenAI TTS default follows whatever sits at `providerDefaults.openai.tts[0]`
   in `model_spec.js` (currently `gpt-4o-mini-tts-2025-12-15`). If a future
   snapshot regresses instruction-following, we reorder that array. This
   keeps one SoT (the providerDefaults list) and avoids a second config
   path via env var. Users who need a specific snapshot can override via
   `~/monadic/config/models.json`.

2. **Instruction token budget — 600 chars (~150 tokens)**

   OpenAI docs don't clarify if `instructions` + `input` are counted
   jointly against the 2000-token limit. A 600-char cap (enforced in the
   system prompt directive, not at parse time) gives substantial safety
   margin and keeps instructions focused. Adjusted if real-world rejections
   are seen.

3. **Speech Draft Helper / AutoForge interaction — no interaction**

   These apps call `text_to_speech` directly from their tool methods, not
   via the WebSocket chat flow. The Expressive Speech pipeline runs only
   on the chat response path. Tool-level calls keep their bespoke
   `instructions` behaviour; Expressive Speech instruction mode adds a
   parallel path for chat responses. Documented in a short note in the
   tool-level apps' internal docs.

4. **Voice selection — gate dropdown by selected TTS model's `tts_voices`**

   `marin` and `cedar` are `gpt-4o-mini-tts`-only. The voice dropdown reads
   the active model's `tts_voices` array from `model_spec.js` and filters
   accordingly. When the user switches TTS models, the dropdown refreshes.
   No silent fallbacks — if a voice isn't supported, it isn't selectable.

5. **Context growth — strip `tts_instructions` before history replay**

   When assembling context for the next LLM turn, strip `tts_instructions`
   from prior assistant messages. The field is per-turn ephemeral metadata
   (affects only the immediate TTS call), not conversational state. This
   prevents token waste on long conversations and also prevents the LLM
   from pattern-matching on its own prior instructions in ways that could
   distort future expressive choices.

## 13. Test plan

### Unit tests

- `spec/unit/utils/tts_text_processors_spec.rb`
  - `family_for("openai-tts-4o")` → `"openai-instruction"`
  - `family_for("openai-tts")` → `"openai"` (unchanged)
  - `family_for("openai-tts-hd")` → `"openai"` (unchanged)
- `spec/unit/utils/tts_instruction_extractor_spec.rb` (new)
  - Valid JSON with both fields → `[message, instructions]`
  - Valid JSON missing `tts_instructions` → `[message, nil]`
  - Valid JSON missing `message` → `[raw, nil]` (fail closed)
  - Invalid JSON → `[raw, nil]`
  - `instruction_mode: false` → `[raw, nil]` unconditionally
- `spec/unit/utils/system_prompt_injector_spec.rb`
  - Instruction-mode family activates new addendum
  - MDSL `expressive_speech false` still disables both rules
- `spec/unit/utils/tts_marker_vocabulary_spec.rb`
  - `prompt_addendum_for("openai-tts-4o")` returns instruction-mode text

### Registry sync

- `spec/unit/utils/tts_registry_sync_spec.rb` — extend with the new family
  mapping parity.

### Integration tests

- `spec/integration/vendors/*_integration_spec.rb` (OpenAI + xAI + Gemini)
  - Send a prompt with instruction-mode on; assert response parses to
    `{ message, tts_instructions }` shape
  - Assert the TTS call (mocked) receives `instructions:` with a non-empty
    string

### Frontend tests

- `test/frontend/ui-expressive-speech-indicator.test.js`
  - Badge shows "instructions" variant when `openai-tts-4o` selected
  - Badge shows "markers" variant for xAI / ElevenLabs v3 / Gemini
  - Badge hidden for `openai-tts` / `openai-tts-hd`

### Manual verification

- Voice Chat app × OpenAI TTS 4o, listen for tonal variation turn-to-turn
- Voice Chat app × xAI Grok LLM + OpenAI TTS 4o (cross-vendor)
- Chat Plus (Monadic) × OpenAI TTS 4o — confirm `context` preserved,
  `tts_instructions` added
- Toggle through TTS providers mid-conversation; confirm badge updates

## 14. Rollout plan

Single-phase rollout. A feature-flagged intermediate phase was considered
but rejected — the L2 fallback already keeps the app functional if anything
goes wrong, so an env-var gate adds complexity without a real safety
benefit. Rollback, if needed, is a `git revert`.

**Implementation order (within one change set):**

1. Backend plumbing
   - `tts_text_processors.rb` — add `openai-instruction` to `family_for`
   - `tts_marker_vocabulary.rb` — add `instruction_mode?` predicate +
     Variant A/B addendum generators; extend `prompt_addendum_for` to
     dispatch by family
   - new `tts_instruction_extractor.rb` — sentinel + JSON parsers +
     history strip helper
   - `system_prompt_injector.rb` — extend the `:expressive_speech` rule
     condition/generator to include instruction-meta family with Monadic
     vs non-Monadic dispatch; add `!instruction_mode?` to the
     `:plain_voice_enforcement` condition
   - `streaming_handler.rb` — post-completion extraction + streaming
     sentinel-stripping state machine for non-Monadic apps
   - `tts_handler.rb` — thread `instructions:` through `start_tts_playback`,
     `start_single_tts_request` to `tts_api_request` (already accepts it)
   - Vendor helpers — add `strip_from_history_json` call at history-write
     sites (Monadic path only)
2. SSOT
   - `model_spec.js` — add `tts_family`, `tts_instructions_capability`,
     `tts_voices` to OpenAI/xAI/Gemini/Mistral/ElevenLabs TTS model entries
   - `model_spec.rb` — Ruby accessors (`tts_family`, `tts_instructions?`,
     `tts_voices`)
3. Frontend
   - `tts-tag-sanitizer.js` — mirror the `family_for` branch
   - `monadic.js` — update `updateExpressiveSpeechIndicator` for the
     instructions-variant badge
   - `markdown-renderer.js` — add `SUPPRESSED_KEYS` set, skip
     `tts_instructions` in `renderField`
   - voice dropdown — filter by active model's `tts_voices`
   - `translations.js` — EN/JA tooltip copy
4. Tests
   - Unit: extractor (sentinel + JSON + strip_from_history), family
     dispatch, injector rule dispatch, vocabulary addendum variants
   - Registry sync
   - Integration: at least OpenAI + xAI cross-vendor mix, Monadic and
     non-Monadic flows
   - Frontend: indicator variants, voice dropdown gating, suppressed-key
     rendering
5. Docs
   - `docs/basic-usage/basic-apps.md` (+ `docs/ja/`) — user-facing explanation
   - `docs_dev/expressive_speech.md` — cross-link this file as the
     instruction-mode companion
   - Brief note in Speech Draft Helper / AutoForge internal docs that
     their tool-level `text_to_speech` calls are independent of this feature

## 15. Related files

- Implementation: `utils/tts_text_processors.rb`, `utils/tts_marker_vocabulary.rb`,
  `utils/system_prompt_injector.rb`, `utils/tts_utils.rb` (already wired),
  `public/js/monadic/tts-tag-sanitizer.js`, `public/js/monadic/model_spec.js`,
  `public/js/monadic.js` (indicator), `views/index.erb` (badge markup)
- Tests: `spec/unit/utils/tts_*_spec.rb`, `test/frontend/ui-expressive-speech-*.test.js`
- Public docs: `docs/basic-usage/basic-apps.md` (+ `docs/ja/`)
- Cross-reference: `docs_dev/expressive_speech.md` (inline-marker families)
- Research source: memory file
  `openai-tts-instructions-research-2026-04-21.md` (openai-fm presets,
  OpenAI API constraints, provider comparison)

## 16. Implementation discoveries (2026-04-22)

Empirical findings from a live-Voice-Chat debugging session on the day of
release. These are not in OpenAI's public documentation and are recorded
here so future maintainers do not have to rediscover them.

### 16.1 Voice × instructions compatibility is the single biggest factor

Running the **exact same** text + instructions + model through the OpenAI
TTS API with only the `voice` parameter changed produces dramatically
different expressiveness:

| Voice | Behaviour with visceral instructions |
|---|---|
| `alloy` | Inconsistent — sometimes natural, sometimes flat |
| `coral` | Consistently natural, dynamic, matches directive |
| `ballad` | Consistently natural, theatrical |
| `verse` | Inconsistent — flat despite dramatic directives |

**Interpretation**: OpenAI voices are not mere timbre variants. `alloy` is
designed for controlled, neutral narration and resists strong directive
changes. `coral` / `ballad` are designed to be expressive and reliably
follow emotional cues. Choosing a voice that "wants" to be expressive is
more important than crafting the perfect directive.

**Action taken**: when `openai-tts-4o` is the selected TTS provider, the
voice dropdown defaults to `coral` (read from
`modelSpec[...].tts_default_voice` as SSOT). Users who explicitly pick
another voice have their 4o-specific preference persisted via a separate
cookie `tts-voice-openai-4o`.

### 16.2 Intensity-matching system-prompt guidance was required

Without explicit guidance, the LLM defaults to mild adjectives ("warm
and playful", "amused and light") even when the user's request is
clearly dramatic ("overreact, laugh out loud"). Mild adjectives produce
mild audio regardless of voice choice.

The addendum now includes `INSTRUCTION_INTENSITY_GUIDANCE` which teaches
the LLM to escalate to **visceral body-state verbs** — "breathless",
"gasping", "trembling", "choked", "bursting", "whispered", "quivering" —
when the reply's emotional register is strong. The engine responds far
more strongly to vivid physical descriptions than to abstract emotion
words alone.

The dramatic example in the addendum was deliberately chosen to model
this style (was: apology scenario with "sincere, empathetic"; now: burst
of laughter with "breathless, barely containing laughter").

### 16.3 Non-factors — things that do NOT affect output quality

- **`response_format: mp3` vs `aac`** — no audible difference when the
  same bytes are played back. Initially suspected as a culprit because
  aac is more compressed, but A/B/C testing with mp3/aac pairs showed
  equivalent quality. Kept default `aac` for the -28 % TTFA benefit.
- **em dash `—` vs plain space** — identical output. The LLM often
  writes `HAHAHA— oh no` and it reads the same as `HAHAHA oh no`.
- **ALL CAPS vs lowercase onomatopoeia (`HAHAHA` vs `hahaha`)** — the
  model interprets both as laughter. Note however that **register
  transitions** matter: `HAHAHAHA oh no` (caps → lowercase) can sound
  jarring when the TTS drops from shouted laughter to quiet prose, but
  this was inconclusive across multiple generations.

### 16.4 Gen-to-gen variance is real

Identical API calls (same model, voice, text, instructions,
response_format) produce slightly different audio each time. Most of the
variance is natural prosody; occasionally the model produces a noticeably
flatter or richer render of the same instruction. We accept this rather
than adding retry logic — a retry only delays the user and adds cost.

### 16.5 The pipeline is innocent

Before touching any prompt/voice tuning, we verified with diagnostic
logging (since reverted) that:
- Sentinel is correctly emitted by the LLM
- Extractor peels it cleanly (`text` = clean reply, `instructions` = the
  directive body)
- `tts_api_request` receives `instructions` as a non-nil string
- The final body sent to `/v1/audio/speech` contains all expected fields

Every failure observed during the session was a **prompt-engineering**
failure (mild instructions, weak voice choice), not a plumbing bug.

### 16.6 Workflow Viewer integration

`public/js/monadic/workflow-viewer.js` now reads runtime state
(`window.params`) at render time:

- When `auto_speech` is on, a `speech` node is inserted before User Input
  (Speech Input / STT, labelled with the current STT model) and after
  Response (Speech Output / TTS, labelled with provider + voice).
- The `Features` side node includes `expressive_speech` when the active
  TTS provider is tag-aware (xAI / ElevenLabs v3 / Gemini) or
  instruction-mode (`openai-tts-4o`).
- `WorkflowViewer.refresh()` is called from the settings-panel change
  handlers (`check-auto-speech`, `tts-provider`, `tts-voice`,
  `stt-model`) so the graph updates live without re-fetching `/api/app`.

This makes the workflow diagram an accurate, live reflection of the
Expressive Speech pipeline the user has configured, not a static
declaration from the MDSL alone.
