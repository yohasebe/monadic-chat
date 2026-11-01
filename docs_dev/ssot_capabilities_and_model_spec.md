# Model Capabilities (SSOT)

`public/js/monadic/model_spec.js` holds the capabilities of every model. The browser reads it directly; Ruby reads it through `Monadic::Utils::ModelSpec`. `~/monadic/config/models.json` is merged over it at load time (entries are added or their properties replaced). The full vocabulary is in [Model Spec Vocabulary](developer/model_spec_vocabulary.md).

## Frequently Used Properties

| Property | Meaning |
|---|---|
| `api_type` | API family, e.g. `"responses"` |
| `tool_capability` | Tool calling |
| `supports_streaming` | Streaming output |
| `vision_capability` | Image input |
| `supports_pdf` / `supports_pdf_upload` | PDF input / PDF file upload |
| `supports_file_inputs` | Other document files as input |
| `supports_web_search` | Native web search |
| `reasoning_effort`, `supports_thinking`, `thinking_budget` | Reasoning controls |

## Attach Button

`ui-utilities.js` shows the attach button when the model has `vision_capability` or the app is an image generation app. Its label:

| Condition | Label | Accepts PDF |
|---|---|---|
| Image generation app (Image Generator for Gemini: Image/PDF) | Image | No |
| `supports_file_inputs` | File | Yes, and other documents |
| PDF upload supported | Image/PDF | Yes |
| Otherwise | Image | No |

PDF upload support is `supports_pdf_upload` when the model sets it, otherwise `supports_pdf` (`isPdfSupportedForModel` in `model-capabilities.js`).

## Naming Rules for Entries

- Add the base model name. Add a dated name only when its capabilities differ from the base, or when no dateless name exists; dated names without an entry resolve to the base entry ([Model Alias and Version Filtering](developer/model_alias_system.md)).
- When a provider offers `-latest` aliases, use the alias.
- Do not add models that are already superseded.
- Speech and music models carry `tts_capability` or `music_capability`; the chat model lists exclude them, and models with `embedding_dimensions`.

## For App Authors

- Gate behavior on capability properties, not model names.
- Let the spec decide what a model offers; app settings decide what the app uses.
