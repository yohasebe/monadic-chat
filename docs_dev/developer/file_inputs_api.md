# OpenAI File Inputs API Integration

## Overview

Monadic Chat integrates the OpenAI File Inputs API to efficiently handle document uploads across conversations. This enables:

1. **File ID caching** — Documents uploaded once via `/v1/files` are cached per session, avoiding redundant base64 re-transmission
2. **Extended format support** — Beyond PDF and images, supports XLSX, DOCX, PPTX, CSV, TXT, MD, JSON, HTML, XML, YAML, and code files (PY, RB, JS, TS, Java, Go, Rust, C/C++, Shell)
3. **URL references** — Responses API models can reference files by URL without downloading

## Architecture

```
Frontend (select_image.js)
  ├── Image → imageToBase64() → { data: base64, type: "image/*" }
  ├── PDF   → fileToBase64()  → { data: base64, type: "application/pdf" }
  ├── Doc   → fileToBase64()  → { data: base64, type: "text/csv" etc. }
  └── URL   → direct          → { data: url, type: mime, source: "url" }
         │
         ▼
Backend (openai_helper.rb)
  ├── document_type?(mime) — classify as document vs image
  ├── resolve_file_id_for_input(session, img)
  │     └── OpenAIFileInputsCache.resolve_or_upload()
  │           ├── Cache hit → return file_id
  │           └── Cache miss → POST /v1/files → cache → return file_id
  │
  ├── Chat Completions message build:
  │     ├── file_id available → { type: "file", file: { file_id: id } }
  │     ├── URL source        → { type: "file", file: { file_url: url } }
  │     └── fallback          → { type: "file", file: { file_data: base64 } }
  │
  └── Responses API conversion:
        ├── file_id → { type: "input_file", file_id: id }
        ├── file_url → { type: "input_file", url: url }
        └── fallback → { type: "input_file", file_data: base64 }
```

## File ID Cache

**Module**: `lib/monadic/utils/openai_file_inputs_cache.rb`

- **Scope**: Session-level (`session[:openai_file_inputs_cache]`)
- **Key**: SHA256(decoded_bytes) + byte_size
- **Upload**: `POST /v1/files` with `purpose: "user_data"`
- **Size limit**: 50 MB per file
- **Failure handling**: Returns `nil`, caller falls back to base64
- **Lifecycle**: Cache cleared when session ends; files auto-deleted by OpenAI after retention period
- **Inline instead**: `resolve_file_id_for_input` returns `nil` (and the file is sent inline as base64) when only part of the data is base64, or when the conversation has words marked for the Privacy Filter

## Model Capability Flag

**Flag**: `supports_file_inputs: true` in `model_spec.js`

Set on the OpenAI models that accept the File Inputs API; see the `supports_file_inputs` entries in `model_spec.js`. Not set on the nano and codex models.

## Frontend UI Tiers

The file selection button adapts based on model capabilities:

| Tier | Condition | Button Text | Accepted Files |
|------|-----------|-------------|----------------|
| 1 | `supports_file_inputs` | "Attach file" | Images + PDF + XLSX, DOCX, code files, etc. |
| 2 | `supports_pdf_upload` (falls back to `supports_pdf`) | "Image/PDF" | Images + PDF |
| 3 | Default | "Image" | Images only |

Image-generation apps skip tiers 1 and 2, except that the Gemini Image Generator accepts PDF.

URL input section is shown only when `api_type === "responses"` AND tier 1 or 2.

## Provider Independence

- `file_id` is an OpenAI-specific concept, stored only in session cache
- Other providers (Claude, Gemini, etc.) use base64 data
- The `images` array in messages carries the same `{ title, data, type }` structure for all providers
- `document_type?()` in `openai_helper.rb` gates document handling to OpenAI only

## Testing

- **Ruby**: `spec/unit/utils/openai_file_inputs_cache_spec.rb`
- **Ruby**: `spec/unit/adapters/vendors/document_mime_types_spec.rb` (DOCUMENT_MIME_TYPES coverage)
- **Ruby**: `spec/unit/adapters/vendors/openai_helper_spec.rb` (document_type? + resolve_file_id_for_input)
- **Frontend**: `test/frontend/select_image.test.js` (getDocumentIcon, isDocumentType, getMimeTypeFromExtension)
- **Frontend**: `test/frontend/utilities.test.js` (isFileInputsSupportedForModel, isResponsesApiModel)
