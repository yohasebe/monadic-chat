# Mermaid Source Sanitization — CJK Safety

Mermaid source for the Mermaid Grapher app is sanitized before validation and rendering: Western smart punctuation that models often write (curly quotes, typographic dashes, fullwidth forms) is folded to ASCII so that the Mermaid parser accepts it.

## Rule

The fold rules must not include CJK characters that only look like Western punctuation:

| Code point | Character | Reason |
| --- | --- | --- |
| U+30FC | long-vowel mark | Part of Japanese words (e.g. クロマトグラフィー); folding it to `-` breaks the word and the Mermaid parse |
| U+300C / U+300D | corner brackets | Japanese quotation and label brackets; folding them to `"` breaks labels |

## Two Implementations

The same rules exist twice and must stay equivalent:

1. **Ruby**: `sanitize_mermaid_code` in `apps/mermaid_grapher/mermaid_grapher_tools.rb`.
2. **JavaScript**: `sanitizeMermaidSource` in `public/js/monadic/ws-content-renderer.js`.

Both carry a `CJK SAFETY` comment that points to this page.

## Tests

- `spec/unit/apps/mermaid_sanitize_cjk_safety_spec.rb`: the long-vowel mark, corner brackets and a Japanese mindmap line survive; Western smart punctuation is folded; no fold `gsub` line contains the CJK code points.
- `test/frontend/websocket-utilities.test.js`: the long-vowel mark is kept; dashes and quotes are folded.

## Render-Error Check in the Preview

`preview_mermaid` validates with a static check (`run_full_validation(…, source: :preview_tool)`) and then renders the diagram in Selenium. Before taking the screenshot it runs `web_navigator.py --action check_render_error`, which reports whether the page shows Mermaid's error graphic (`svg[aria-roledescription="error"]`, `.error-icon`, `.error-text`). On an error, `preview_mermaid` returns a failure with the error text instead of a screenshot. Covered by `spec/unit/apps/mermaid_preview_render_error_spec.rb`.

The preview page initializes Mermaid with `securityLevel: 'loose'`; the chat renderer uses `'strict'`.
