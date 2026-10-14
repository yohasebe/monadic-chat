# Mermaid Grapher

Mermaid Grapher has OpenAI, Claude, Gemini and Grok variants. All use `MermaidGrapherTools` (`apps/mermaid_grapher/mermaid_grapher_tools.rb`) and differ only in their LLM settings.

## Tools

| Tool | What it does |
|---|---|
| `validate_mermaid_syntax(code:)` | Validates with Mermaid in a headless Selenium session (`mermaid_test_*.html`, removed after use); static checks when Selenium fails |
| `preview_mermaid(code:)` | Renders the diagram in the browser session and returns a screenshot to the model |
| `stop_mermaid_browser` | Ends the browser session (`web_navigator.py --action stop`) and removes `mermaid_live_*.html` |
| `analyze_mermaid_error(code:, error:)` | Suggests fixes for an error message |
| `fetch_mermaid_docs(diagram_type:)` | Returns the mermaid.js.org syntax page URL for a diagram type (the introduction page for unknown types) |

## Preview

`preview_mermaid`:

1. Normalizes the code and runs the static validation (not Selenium: the preview needs the single Selenium slot).
2. Writes `mermaid_live_<time>_<hex>.html` to the shared folder.
3. Calls `web_navigator.py` in the Python container: `--action navigate` when `/monadic/data/.browser_session_id` exists (falling back to `--action start` if that fails), otherwise `--action start`.
4. Waits 3 seconds, then `--action check_render_error`: Mermaid's error graphic makes the tool fail with "Diagram render error".
5. `--action full_screenshot` saves `mermaid_preview_<time>_<hex>.png`, or several tiles for a tall diagram.
6. Returns the file names under `_image`, so the model sees the screenshot. No `gallery_html` is sent; the chat shows the diagram as SVG from the client-side `MarkdownRenderer`.

Afterwards, every `mermaid_live_*.html` except the current one is removed, and `mermaid_preview_*.png` files older than 600 seconds (`PREVIEW_IMAGE_MAX_AGE`).

Web Insight uses the same `.browser_session_id`; `--action start` ends any existing session, so switching apps ends the other app's browser session.

## Normalization

`sanitize_mermaid_code` (Ruby):

- decode HTML entities; `\r\n` and U+2028/U+2029 become newlines; `\"` and literal `\n` are unescaped;
- Western dashes and minus signs (U+2010–2015, U+2212, U+FF0D) become `-`; curly and full-width quotes become `'` or `"`; `／` becomes `/`;
- inside `[…]`, blank lines are collapsed and line breaks become `<br/>`;
- trailing spaces and empty lines are removed.

`sanitizeMermaidSource` (`ws-content-renderer.js`) applies the newline, entity, dash and quote rules to the diagram shown in the chat.

Both leave the Japanese long-vowel mark (U+30FC) and corner brackets (「」) as they are; specs on both sides check this.

In the preview HTML only `&`, `<` and `>` are escaped (`escape_mermaid_code_for_html`).

## Labels

The system prompts tell the model to write node IDs and class names in English and labels in the user's language.
