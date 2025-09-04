# ModelSpec for Providers and Models

This guide explains how Monadic Chat loads model capabilities and how you can extend/override them for development and testing.

## Overview

Model capabilities (vision/tool/streaming/JSON support, context window, labels, etc.) are defined in a default spec bundled with the web UI and are loaded at runtime, then merged with optional user overrides.

## Where Specs Come From

- Default spec: shipped with the app in a JavaScript file that defines a `const modelSpec = { ... }` object (used by the web UI).
- Ruby side loader: `docker/services/ruby/lib/monadic/utils/model_spec_loader.rb` reads the default JS file, extracts the `modelSpec` object safely, and parses it as JSON.
- User overrides: optional file at `~/monadic/config/models.json` (or `/monadic/config/models.json` inside the container).

## Merge Rules

- Deep merge: the loader performs a recursive merge, where user values override defaults and nested objects merge key-by-key.
- Invalid JSON in `models.json` is ignored with a warning; the default spec is used as a fallback.
- Unknown keys are preserved; use with care.

## Typical Use Cases

- Adding a new model alias
- Overriding default model choices (e.g., `OPENAI_DEFAULT_MODEL`)
- Adjusting capability flags (e.g., `tool_capability`, `supports_thinking`)

## Environment Defaults

- Some defaults can be set via environment variables (e.g., `OPENAI_DEFAULT_MODEL`, `ANTHROPIC_DEFAULT_MODEL`, `GEMINI_DEFAULT_MODEL`, etc.).
- See `docker/services/ruby/lib/monadic/utils/system_defaults.rb` for provider→ENV mapping.

## Validation & Tests

- Frontend: `test/frontend/model_spec.test.js` verifies that the `modelSpec` object is correctly structured and key capabilities exist.
- Backend: `docker/services/ruby/spec/unit/model_spec_loader_spec.rb` tests merging behavior and robustness of the loader.

## Tips

- Keep changes minimal and documented.
- When adding brand-new models, be explicit about capabilities to avoid surprises.
- For OpenAI Responses API detection and websearch support, ensure new GPT-5 variants are recognized where needed.

## User Override Example (`~/monadic/config/models.json`)

```json
{
  "openai": {
    "gpt-5-custom": {
      "label": "GPT-5 (Custom Alias)",
      "vision_capability": true,
      "tool_capability": true,
      "streaming_capability": true,
      "supports_verbosity": true,
      "context_window": [1, 500000]
    }
  },
  "anthropic": {
    "claude-3-5-haiku-20241022": {
      "label": "Claude 3.5 Haiku (Override)",
      "vision_capability": false,
      "tool_capability": true
    }
  }
}
```

Notes
- Place this file at `~/monadic/config/models.json` (or `/monadic/config/models.json` inside container).
- Unknown keys are preserved; prefer well-known keys for compatibility.
- If parsing fails, the system falls back to the default spec with a warning.
