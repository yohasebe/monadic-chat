# Client-Side Rendering Pipeline

Last updated: 2025-11-08

## Overview

All HTML generation for chat cards now happens in the browser. The Ruby server sends raw
`msg.text` (Markdown or Monadic JSON) together with metadata (`app_name`, `monadic`,
flags for MathJax/ABC/Mermaid, etc.). The front-end converts that payload into styled HTML
using `MarkdownRenderer`.

```
Ruby (websocket.rb)
  └─ sends { text, app_name, monadic, ... }

Browser
  ├─ renderMessage()
  │   └─ MarkdownRenderer.render(text, { appName, isMonadic })
  │        ├─ Monadic JSON? → jsonToHtml()
  │        └─ Markdown?     → renderMarkdown()
  │
  └─ MarkdownRenderer.applyRenderers(cardElement)
      ├─ highlight.js
      ├─ MathJax.typesetPromise()
      ├─ applyAbc() / ABCJS fallback
      └─ applyMermaid() / mermaid.run() fallback
```

## MarkdownRenderer responsibilities

### 1. Entry point

```js
MarkdownRenderer.render(text, { appName, isMonadic })
```

- Detects Monadic JSON vs normal Markdown
- Parses Monadic payloads (AutoForge, Chat Plus, etc.) via `jsonToHtml`
- Normal Markdown paths keep MathJax/ABC/Mermaid blocks as placeholders until after rendering

### 2. Monadic JSON support

- `isMonadicJson()` checks the explicit `isMonadic` flag, app name (`chat_plus_*`, `auto_forge_*`, `concept_visualizer_*`) and JSON structure
- `renderMonadicJson()` mirrors Ruby’s `monadic_html` layouts (message first, collapsible context sections, citation formatting)

### 3. Markdown rendering

- markdown-it renders text → HTML
- MathJax, ABC, Mermaid blocks are temporarily replaced with placeholders (`MATH_BLOCK_PLACEHOLDER_x`, `ABC_BLOCK_PLACEHOLDER_x`, `MERMAID_BLOCK_PLACEHOLDER_x`)
- After HTML is produced, placeholders are replaced with `<div class="abc-code"><pre>…</pre></div>` or `<div class="mermaid-code"><pre>…</pre></div>`

### 4. Unified post-processing

`MarkdownRenderer.applyRenderers(container)` runs after a card is inserted into the DOM:

| Feature   | Implementation                                                                 | Notes                                     |
|-----------|---------------------------------------------------------------------------------|-------------------------------------------|
| Code      | `window.SyntaxHighlight.apply()` (highlight.js)                                 | executed via `requestIdleCallback`        |
| MathJax   | `MathJax.typesetPromise([container])`                                           | idle/raf fallback                         |
| ABC       | prefers existing `applyAbc(jQueryElement)`; falls back to `ABCJS.renderAbc()`  | works with `.abc-code` or `.abc-notation` |
| Mermaid   | prefers `applyMermaid(jQueryElement)`; falls back to `mermaid.run()`           | handles `.mermaid` & `.mermaid-code`      |

Processing is scheduled via `requestIdleCallback` (with raf/setTimeout fallback) to avoid UI stalls when many cards are appended simultaneously.

## Server expectations

To keep client rendering deterministic, the server must send:

- `text`: Markdown or Monadic JSON (raw string, no HTML)
- `app_name`: canonical snake_case name (e.g., `chat_plus_openai`)
- `monadic`: boolean flag when the app uses Monadic JSON responses
- Feature flags (MathJax, Mermaid, ABC) in `params`

`renderMessage()` on the client fills gaps by looking at SessionState/params, but the goal is to always send accurate metadata from Ruby so the browser does not need to guess.

## Tab isolation

Each browser tab maintains completely independent session state:

- **Tab Identifier**: Unique `tab_id` (UUID) generated per tab, stored in `sessionStorage`
- **WebSocket Connection**: Each tab connects with `ws://localhost:4567/?tab_id={UUID}`
- **Server-Side Storage**: Ruby maintains `@@session_state` hash keyed by `tab_id`
- **Session Persistence**: Page refresh within same tab preserves session via `tab_id`
- **Independence**: Messages, parameters, and app selection are tab-specific

**Key Implementation Details**:

1. `sessionStorage` (not `localStorage`) ensures tab-specific data
2. WebSocket initialization occurs after `ensureMonadicTabId()` is defined
3. Server always clears Rack session on connect, then restores from `@@session_state[tab_id]`
4. Parameters are always broadcast (even if empty) to prevent localStorage pollution

See `docs_dev/frontend/tab_isolation.md` for complete architecture details.

## When adding new stylized content

1. Update the server to send raw source text + metadata.
2. In `MarkdownRenderer.render()`, detect the new block type and insert a placeholder.
3. Extend `applyRenderers()` (or reuse `applyXxx()` helpers) to transform placeholders into final DOM nodes.
4. Keep heavy work inside `requestIdleCallback` to avoid blocking animation frames.

By following this pattern, new content types behave like MathJax/ABC/Mermaid/Monadic without reintroducing server-side HTML generation.
