# Mermaid Source Sanitization — CJK Safety Policy

## Summary

Mermaid source typed/generated for the Mermaid Grapher app is "sanitized"
before validation and rendering: Western *smart* punctuation that LLMs often
emit (curly quotes, typographic dashes, fullwidth forms) is folded back to
ASCII so the Mermaid parser does not choke on it.

**These fold rules MUST NOT include CJK characters that merely look like
Western punctuation.** Never add the following to the fold character classes:

| Code point | Char | Why it must be preserved |
| --- | --- | --- |
| U+30FC | long-vowel mark | Japanese prolonged sound (e.g. クロマトグラフィー). Folding to `-` corrupts katakana words. |
| U+300C / U+300D | corner brackets | Japanese quotation/label brackets. Folding to `"` corrupts labels. |

## Background (the bug this policy prevents)

2026-06-02: A chemistry mindmap with the node クロマトグラフィー failed to render
with **"Syntax error in text — mermaid version 11.4.1"**, even though the tool
reported *"Done — verified successfully"*.

Root cause: both sanitizers folded the long-vowel mark (U+30FC) to ASCII `-`,
turning クロマトグラフィー into a katakana word ending in a stray hyphen.
Mermaid's `mindmap` parser then failed on the hyphen. The "verified
successfully" message was misleading because the **preview path skips Selenium
validation and uses a lenient static check** (`run_full_validation` with
`source: :preview_tool`), which did not flag the corrupted text — so validation
and rendering disagreed.

## The two mirrored implementations (keep them in sync)

The same fold ruleset is implemented twice and must stay equivalent:

1. **Server (Ruby)** — `apps/mermaid_grapher/mermaid_grapher_tools.rb`,
   `sanitize_mermaid_code`.
2. **Frontend (JS)** — `public/js/monadic/ws-content-renderer.js`,
   `sanitizeMermaidSource`.

Both carry a `CJK SAFETY` comment block pointing at this document.

## Regression guards

CJK safety is pinned on both stacks; a re-introduction of the long-vowel mark
or corner brackets into a fold rule (or a behavioral regression) fails these:

- **Ruby**: `spec/unit/apps/mermaid_sanitize_cjk_safety_spec.rb`
  - behavioral: long-vowel / corner brackets / a Japanese mindmap line survive
    sanitization; Western smart punctuation is still folded.
  - source guard: no fold `gsub` line contains the CJK code points.
- **Frontend (Jest)**: `test/frontend/websocket-utilities.test.js`
  - behavioral: long-vowel and クロマトグラフィー are preserved; dashes/quotes folded.

## Render-error gating (the structural fix)

The deeper structural issue behind the original report was that the **preview
path validated with a lenient static check while the real render happened in
the browser**, so a sanitizer bug (or any other defect) could pass validation
yet fail rendering — and the screenshot step would happily capture Mermaid's
error graphic (the "bomb" icon) and report success.

This is now closed. `preview_mermaid` consults a dedicated web_navigator
action, `check_render_error`, between rendering and screenshotting:

- **`check_render_error`** (`docker/services/python/scripts/cli_tools/web_navigator.py`)
  runs JS in the live page and reports whether the rendered SVG is Mermaid's
  error graphic (`svg[aria-roledescription="error"]` / `.error-icon` /
  `.error-text`), returning `{render_error: bool, error_text}`.
- **`preview_mermaid`** (`mermaid_grapher_tools.rb`) returns a failure with the
  error detail when `render_error` is true, instead of capturing and presenting
  the error screen. The LLM then sees the real Mermaid error and can self-correct.

Pinned by `spec/unit/apps/mermaid_preview_render_error_spec.rb` (render-error →
failure, clean render → proceeds to screenshot).

### Remaining minor divergence (low priority)

`build_mermaid_html` initializes Mermaid with `securityLevel: 'loose'`, while the
chat renderer (`ws-content-renderer.js`) uses `'strict'`. The preview therefore
renders under slightly more permissive settings than the chat surface. The
render-error gate catches outright parse failures regardless, but a diagram that
only fails under `strict` could still pass preview. Aligning the two security
levels is a separate, lower-priority cleanup.
