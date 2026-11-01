# Expressive Speech

When Auto Speech is on, the system prompt tells the model how to shape its reply for the selected Text-to-Speech engine: inline markers (`[laugh]`, `<whisper>…</whisper>`), a style directive, or plain prose. The markers and directives are removed from what the user sees. This page covers the marker families; the directive (instruction mode) is described in [`expressive_speech_instruction_mode.md`](expressive_speech_instruction_mode.md).

## Families

`TtsTextProcessors.family_for(provider)` (`lib/monadic/utils/tts_text_processors.rb`) maps the `#tts-provider` value to a family: the value names a model in `ttsChoices` (`model_spec.js`), and the family is that model's `tts_family`. `tts-tag-sanitizer.js` has the same function; both are checked against `spec/fixtures/tts/families_expected.json`.

| Provider value | Family | Mode |
|---|---|---|
| `grok` | `xai` | inline and wrap markers |
| `elevenlabs-v3`, `elevenlabs-v4`, `elevenlabs-v4-turbo` | `elevenlabs-v3` | inline markers |
| `elevenlabs-flash`, `elevenlabs-multilingual` | `elevenlabs` | plain prose |
| `gemini-flash`, `gemini-flash-lite` | `gemini` | hybrid: inline markers and a directive |
| `openai-tts-4o` | `openai-instruction` | directive (instruction mode) |
| `openai-tts`, `openai-tts-hd` | `openai` | plain prose |
| `mistral` | `mistral` | plain prose |
| `webspeech` | `webspeech` | plain prose |

## System Prompt

Two rules in `SystemPromptInjector` (`lib/monadic/utils/system_prompt_injector.rb`), both off unless `__expressive_speech_active?` is true (Auto Speech on, and the app has not set `expressive_speech false` in its MDSL `features`):

| Rule | Priority | Condition | Text |
|---|---|---|---|
| `:expressive_speech` | 30 | marker family or `openai-instruction` | `TtsMarkerVocabulary.prompt_addendum_for(provider, app_is_monadic:)` |
| `:plain_voice_enforcement` | 29 | any other selected provider | "output plain prose only", and ignore markers in earlier turns |

`TtsMarkerVocabulary` (`lib/monadic/utils/tts_marker_vocabulary.rb`) holds the marker lists in `VOCABULARIES` (`xai`, `elevenlabs-v3`, `gemini`). `prompt_addendum_for` returns:

- `hybrid_addendum_for` for `gemini` (markers plus an optional directive: a `tts_instructions` field in Monadic apps, a leading `<<TTS:...>>` block otherwise);
- `marker_addendum_for` for `xai` and `elevenlabs-v3`;
- `instruction_addendum` for `openai-instruction`;
- nil otherwise.

The marker addendum lists the markers, gives examples, and forbids naming them in the reply or opening a conversation with one.

| Family | Inline markers | Wrap tags |
|---|---|---|
| `xai` | pause long-pause laugh sigh cry inhale exhale click smack | whisper soft loud fast slow high low sing |
| `elevenlabs-v3` | see `VOCABULARIES["elevenlabs-v3"]` | — |
| `gemini` | amazed crying curious excited sighs gasp giggles laughs mischievously panicked sarcastic serious shouting tired trembling whispers | — |

## Text Sent to the Engine

`tts_text_as_sent` (`lib/monadic/utils/tts_utils.rb`) applies `TTS_DICT`, then `TtsTextProcessors.pre_send(provider, text)`. For the three marker families, `PRE_SEND` calls `translate_markers(text, family)`:

1. **Concepts**: `INLINE_CONCEPTS` (laugh, giggle, sigh, cry, pause, long_pause, inhale, exhale) matches any known spelling and writes the target family's form, or removes it when the target has none (for example `[pause]` for ElevenLabs v3 and Gemini).
2. **Wraps** (ElevenLabs v3 and Gemini only): `<whisper>X</whisper>` becomes `[whispers] X`; other xAI wraps and orphan `<whisper>` / `</whisper>` tags are removed.
3. **Foreign markers**: `FOREIGN_MARKER_RE[family]` removes markers that belong only to other families.

Brackets that are not known markers (`[1]`, `[TODO]`) are left in place. For `xai`, malformed wraps are left as they are.

| Input | Target `xai` | Target ElevenLabs v3 / Gemini |
|---|---|---|
| `<whisper>hello [laugh] friend</whisper>` | unchanged | `[whispers] hello [laughs] friend` |
| `<loud>big <whisper>quiet</whisper> end</loud>` | unchanged | `big [whispers] quiet end` |
| `<whisper>A<whisper>nested</whisper>B</whisper>` | unchanged | `[whispers] AnestedB` |
| `<whisper>unclosed` | unchanged | `unclosed` |

## Display

`TtsTextProcessors.sanitize_for_display(provider, text)` and `TtsTagSanitizer.sanitizeForDisplay` (JS) run when the selected provider has an entry in `DISPLAY_SANITIZE` (`xai`, `elevenlabs-v3`, `gemini`, `openai-instruction`):

- The selected family's sanitizer runs in full. The ElevenLabs v3 and Gemini sanitizers include a lowercase catch-all for improvised descriptors; the Gemini and `openai-instruction` sanitizers also remove a leading `<<TTS:...>>` block.
- The other families' markers are removed with their fixed lists only (`*_STRICT_RE`), so brackets like `[done]` stay.
- A leading `<<TTS:...>>` block is removed for every other family too.

`markdown-renderer.js` calls the JS sanitizer in `render()`, so finished cards (streamed or loaded) are clean. While a reply streams, fragments are shown as they arrive and can show markers until the card is rendered.

`spec/unit/utils/tts_registry_sync_spec.rb` checks that the Ruby and JS marker lists and `family_for` agree. The translation step exists only in Ruby.

## UI

- `updateExpressiveSpeechIndicator()` (`public/js/monadic.js`) shows `#expressive-speech-indicator` when Auto Speech is on and `TtsTagSanitizer.tagAware(provider)` is true. The tooltip is `ui.expressiveSpeechInstructionsTooltip` for `openai-instruction` and `ui.expressiveSpeechTooltip` otherwise. It also calls `applyOpenAIVoiceGating`, which hides voices marked `data-tts-4o-only` unless the provider is `openai-tts-4o`.
- The Workflow Viewer (`public/js/monadic/workflow-viewer.js`) adds speech input and output nodes when Auto Speech is on, and lists `expressive_speech` among the features when the provider is a marker family or `openai-instruction`. The settings handlers call `WorkflowViewer.refresh()`.

## Adding a Marker Family

1. Map the provider value(s) to the family in `family_for` (Ruby and JS).
2. Add a `DISPLAY_SANITIZE` entry in Ruby and JS. If the engine accepts free-form descriptors, add a catch-all to it and a fixed-list `*_STRICT_RE` for cross-family cleanup.
3. Add the marker list and examples to `TtsMarkerVocabulary::VOCABULARIES`.
4. In Ruby: add the family to each relevant `INLINE_CONCEPTS[:emit]`, to `FOREIGN_MARKER_RE`, and to `PRE_SEND`.
5. Add the family to the tooltip text in `public/js/i18n/translations.js` and to the user documentation (EN/JA).
6. Run `npm test` and `bundle exec rspec spec/unit/utils/tts_*` (from `docker/services/ruby`).

Give a family key only to the engine versions that interpret markers; other versions of the same brand map to a plain family (as `elevenlabs-flash` and `elevenlabs-multilingual` do).

## Tests

| Spec | Covers |
|---|---|
| `spec/unit/utils/tts_text_processors_spec.rb` | `family_for`, translation, display sanitizers |
| `spec/unit/utils/tts_marker_vocabulary_spec.rb` | vocabularies, addendum contents |
| `spec/unit/utils/tts_instruction_extractor_spec.rb` | `<<TTS:...>>` and JSON extraction |
| `spec/unit/utils/system_prompt_injector_spec.rb` | `:expressive_speech` / `:plain_voice_enforcement` conditions, MDSL opt-out |
| `spec/unit/utils/tts_registry_sync_spec.rb` | Ruby and JS lists agree |
| `test/frontend/tts-tag-sanitizer.test.js` | JS sanitizer |
