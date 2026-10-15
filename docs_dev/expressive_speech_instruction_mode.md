# Expressive Speech — Instruction Mode

In instruction mode the model writes a short voice directive (voice, tone, pacing, …) next to its reply. The directive is sent to the TTS engine and never shown. It is used for the `openai-instruction` family (provider value `openai-tts-4o`) and, together with inline markers, for the `gemini` family. Families and the marker mode: [`expressive_speech.md`](expressive_speech.md).

## Which Providers

| Check (`TtsMarkerVocabulary`) | True for |
|---|---|
| `instruction_mode?(provider)` | `openai-instruction` |
| `instruction_capable?(provider)` | `openai-instruction`, `gemini` |

In `model_spec.js`, TTS models carry `tts_family` and `tts_instructions_capability`; `ModelSpec.tts_instructions?(model)` reads the latter.

## What the Model Is Asked For

The `:expressive_speech` rule (priority 30) adds the addendum when Auto Speech is on and the app has not set `expressive_speech false`. The directive has six lines from `INSTRUCTION_ATTRIBUTE_TEMPLATE` (Voice, Tone, Pacing, Emotion, Pronunciation, Pauses), stays under 600 characters, and follows `INSTRUCTION_INTENSITY_GUIDANCE` (neutral wording for neutral content, vivid physical wording for strong emotion). The reply itself must be plain prose.

| Family | App | Addendum | Encoding |
|---|---|---|---|
| `openai-instruction` | Monadic app | `instruction_addendum_json` | a top-level `tts_instructions` field beside `message` and `context` |
| `openai-instruction` | other app | `instruction_addendum_sentinel` | `<<TTS:directive>>` at the start, then the reply |
| `gemini` | Monadic app | `hybrid_addendum_for` | an optional top-level `tts_instructions` field, plus inline markers in `message` |
| `gemini` | other app | `hybrid_addendum_for` | optional `<<TTS:directive>>` at the start, plus inline markers |

`SystemPromptInjector.__app_is_monadic?` decides the app type from the session's `monadic` parameter, then the MDSL `monadic` setting. `:plain_voice_enforcement` is not added for `openai-instruction`.

## Extraction

`Monadic::Utils::TtsInstructionExtractor` (`lib/monadic/utils/tts_instruction_extractor.rb`) never raises; when it finds nothing it returns the text unchanged with nil.

- `extract(text, app_is_monadic:)` → `[reply, directive_or_nil]`, using `extract_json` (Monadic apps: `message` and `tts_instructions`) or `extract_sentinel` (others: `SENTINEL_RE = /\A\s*<<TTS:(.*?)>>\s*/m`).
- `strip_from_history(text, app_is_monadic:)` removes the `tts_instructions` key or the leading block.
- `possibly_sentinel_start?` / `try_consume_sentinel` support streaming.

In `streaming_handler.rb`:

- **Streaming**: for non-Monadic apps with Auto Speech on and an instruction-capable provider, fragments are held back while the text could still be the start of `<<TTS:`. A complete block is dropped and the rest is forwarded; anything else is forwarded at once.
- **TTS**: after the reply completes, `extract` runs on the text (not on a `tts_target` text) and the directive is passed to `start_tts_playback(..., instructions:)`. Without a directive, the reply is spoken without one.

`html_handler.rb` runs `strip_from_history` before the assistant message is stored, so the next request does not carry the directive.

## TTS Request

`tts_api_request(..., instructions:)` (`lib/monadic/utils/tts_utils.rb`):

- **OpenAI** (`openai-tts-4o`, `openai-tts`, `openai-tts-hd`): `instructions` is added to the `/audio/speech` body when present.
- **Gemini**: the directive goes into the text, according to the model's `tts_style_directive` in `model_spec.js`:

| `tts_style_directive` | Prefix |
|---|---|
| not set | `"Say with this voice and style:\n<directive>\n\n"` |
| `bracket_cue` | `[<directive on one line>] ` |
| `omit` | none |

## Display

- Sentinel: `DISPLAY_SANITIZE["openai-instruction"]` and `["gemini"]` (Ruby and JS) remove a leading `<<TTS:...>>` block; `sanitize_for_display` removes it for every other family as well.
- JSON: `markdown-renderer.js` skips the keys in `MONADIC_SUPPRESSED_KEYS` (`tts_instructions`) when it renders a Monadic response.

## UI

- The Expressive Speech badge uses the tooltip `ui.expressiveSpeechInstructionsTooltip` for `openai-instruction`.
- `applyOpenAIVoiceGating` (`public/js/monadic.js`) shows the voices marked `data-tts-4o-only` only for `openai-tts-4o`; a hidden selected voice falls back to `alloy`. On switching to `openai-tts-4o`, the saved 4o voice (cookie `tts-voice-openai-4o`) or the `tts_default_voice` of `providerDefaults.openai.tts[0]` is selected.

## Tests

- `spec/unit/utils/tts_instruction_extractor_spec.rb`
- `spec/unit/utils/tts_marker_vocabulary_spec.rb`
- `spec/unit/utils/system_prompt_injector_spec.rb`
- `spec/unit/utils/tts_text_processors_spec.rb`, `spec/unit/utils/tts_registry_sync_spec.rb`
- `test/frontend/tts-tag-sanitizer.test.js`
