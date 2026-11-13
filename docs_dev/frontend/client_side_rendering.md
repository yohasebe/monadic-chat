# Client-Side Rendering Pipeline

## Overview

All HTML generation for chat cards happens in the browser. The Ruby server sends raw
`msg.text` (Markdown) together with metadata (`app_name`, flags for KaTeX/ABC/Mermaid,
etc.). The front-end converts that payload into styled HTML
using `MarkdownRenderer`.

```
Ruby (websocket.rb)
  └─ sends { text, app_name, ... }

Browser
  ├─ renderMessage()
  │   └─ MarkdownRenderer.render(text)
  │        └─ renderMarkdown()
  │
  └─ MarkdownRenderer.applyRenderers(cardElement)
      ├─ highlight.js
      ├─ KaTeX (inline via renderMarkdown placeholders)
      ├─ applyAbc() / ABCJS fallback
      └─ applyMermaid() / mermaid.run() fallback
```

## MarkdownRenderer responsibilities

### 1. Entry point

```js
MarkdownRenderer.render(text)
```

- Renders the text as Markdown, the same way in every app
- KaTeX/ABC/Mermaid blocks are kept as placeholders until after rendering

### 2. Markdown rendering


- markdown-it renders text → HTML
- KaTeX, ABC, Mermaid blocks are temporarily replaced with placeholders (`MATH_BLOCK_PLACEHOLDER_x`, `ABC_BLOCK_PLACEHOLDER_x`, `MERMAID_BLOCK_PLACEHOLDER_x`)
- After HTML is produced, KaTeX placeholders are replaced with rendered math HTML, ABC/Mermaid placeholders with `<div class="abc-code"><pre>…</pre></div>` or `<div class="mermaid-code"><pre>…</pre></div>`

### 3. Unified post-processing

`MarkdownRenderer.applyRenderers(container)` runs after a card is inserted into the DOM:

| Feature   | Implementation                                                                 | Notes                                     |
|-----------|---------------------------------------------------------------------------------|-------------------------------------------|
| Code      | `window.SyntaxHighlight.apply()` (highlight.js)                                 | executed via `requestIdleCallback`        |
| KaTeX     | Rendered inline during `renderMarkdown()` via placeholders                      | `katex.renderToString()` at build time    |
| ABC       | `applyAbc(element)` or `ABCJS.renderAbc()` fallback                            | works with `.abc-code` or `.abc-notation` |
| Mermaid   | `applyMermaid(element)` or `mermaid.run()` fallback                             | handles `.mermaid` & `.mermaid-code`      |

Processing is scheduled via `requestIdleCallback` (with raf/setTimeout fallback) to avoid UI stalls when many cards are appended simultaneously.

## Server expectations

To keep client rendering deterministic, the server must send:

- `text`: Markdown (raw string, no HTML)
- `app_name`: the app's name
- Feature flags (KaTeX, Mermaid, ABC) in `params`

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

By following this pattern, new content types behave like KaTeX/ABC/Mermaid/Monadic without reintroducing server-side HTML generation.
