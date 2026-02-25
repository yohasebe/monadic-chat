# Mermaid Grapher: Rendering Notes

## Multi-Provider Support

Mermaid Grapher is available for OpenAI, Claude, Gemini, and Grok. All providers share the same tool module (`MermaidGrapherTools`) and differ only in LLM configuration (provider, model, API key gate).

## Live Browser Preview (noVNC)

`preview_mermaid` uses `web_navigator.py` to render diagrams in a non-headless Chrome browser visible via noVNC (`http://localhost:7900`).

- **First call**: `--action start` creates a new browser session and navigates to the generated HTML
- **Subsequent calls**: `--action navigate` updates the same browser with a new HTML file
- **Session detection**: checks `/monadic/data/.browser_session_id` file existence
- **Fallback**: if navigate fails (session expired), automatically falls back to `--action start`
- **Screenshot**: `--action screenshot` captures the rendered diagram as PNG

The noVNC window auto-opens in Electron when `preview_mermaid` executes (via `websocket.js` trigger).

Call `stop_mermaid_browser` to end the session and clean up HTML files.

### Session Sharing with VWE

Mermaid Grapher and Web Insight share the same `.browser_session_id` file. `--action start` automatically cleans up any existing session, so switching between apps is safe but will terminate the other app's browser session.

## Unicode Normalisation

Mermaid.js expects ASCII arrows (`-->`) and plain quotes inside labels. Recent GPT outputs occasionally include:

- Unicode dashes (`–`, `—`, `ー`, etc.) in place of `-`
- Smart quotes (`""`, `''`, `「」`)
- Full-width slashes (`／`) or repeated blank lines inside brackets

Before validation/rendering we normalise:

- decode any HTML entities returned by the LLM
- replace unicode dashes with `-`
- convert smart quotes / Japanese-style quotes to ASCII
- collapse blank lines inside `[ ... ]` and rewrite line breaks as `\n`

Keep these steps if you touch `sanitize_mermaid_code` or `sanitizeMermaidSource`.

## HTML embedding

When embedding Mermaid code into the preview HTML, we escape only `<`, `>` and `&`. Quotes stay literal so labels render correctly. Any future change must preserve this behaviour.

## HTML File Lifecycle

- Preview HTML files are named `mermaid_live_[timestamp].html`
- During a live session, the latest HTML is kept (browser is displaying it); older files are cleaned up
- `stop_mermaid_browser` removes all `mermaid_live_*.html` files
- Validation HTML files (`mermaid_test_*.html`) are cleaned up immediately after use

## Validation

`preview_mermaid` runs `run_full_validation` internally before rendering. The validation uses a separate headless Selenium session (inline Python) that does not interfere with the live preview session.

Fallback order: Selenium validation → static syntax validation (if Selenium unavailable).

## Frontend helper

`sanitizeMermaidSource` mirrors the backend normalisation so the Mermaid snippet inside `<mermaid>` matches the preview PNG output. If you modify the backend logic, update the frontend helper accordingly.
