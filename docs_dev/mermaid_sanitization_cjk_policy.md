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

## Known follow-up (separate task)

The deeper structural issue — the **preview path validates with a lenient
static check while rendering happens elsewhere**, so a sanitizer bug can pass
validation yet fail rendering — is intentionally out of scope here. Making the
preview path's validation reflect the actual render (subject to the single
Selenium Grid slot constraint, see `run_full_validation` comments) is tracked
separately. Until then, the CJK-safety guards above prevent the specific class
of corruption that triggered the original report.
