# Drawing content in the page

The page draws some kinds of content: in the work screen, text files of the shared folder (Markdown, Mermaid diagrams, CSV/TSV tables, SVG, static HTML pages and Vega-Lite charts); in the chat's cards, Mermaid diagrams. Input never runs as code, and output that was not sanitized never enters the page's DOM; nothing drawn reaches the network.

## The table of kinds

`lib/monadic/render_formats.json` names each kind (`id`), the code fence languages and the file extensions it is known by (`compound_extensions`, such as `vl.json`, are looked at first). `Monadic::RenderFormats` (`lib/monadic/render_formats.rb`) reads and checks it (no id, fence or extension named twice); `SharedFolderPreview.render_for` and `Workbench::Put` use it. The page is given the same table in `<script type="application/json" id="render-formats">` (`views/index.erb`), which `render-registry.js` reads. `test/fixtures/render_format_cases.json` holds the cases both sides are tested with.

## Diagrams in the chat

`render-registry.js` (`Renderers.apply(container)`) draws each `div.mermaid-code` placeholder that `markdown-renderer.js` makes from a ```` ```mermaid ```` fence: the source (made plain by `sanitizeMermaidSource`) is drawn with `WorkbenchRender` (the same frame as the work screen) and shown as an image with **Download SVG**; the source stays in the placeholder behind a switch. A placeholder is drawn once (the same source again does nothing while it is drawn or being drawn; a drawing that failed is drawn again only from its **Try again**; a new source lets the old drawing go). One `MutationObserver` lets go of the drawings whose placeholder left the document, and keeps the switch and the drawing beside a placeholder that was moved. The PDF export (`pdf_export.js`) prints a copy of the card (`Renderers.printable`): each drawn diagram as a `data:` image of its own, and one still drawing or failed as its source, shown; the card is not changed. `MarkdownRenderer.applyRenderers` and the edit and sample paths of `ws-message-renderer.js` call it for every app; the MDSL `mermaid` flag only adds the writing guidance to the system prompt and the badge.

## Server

- `SharedFolderPreview.render_for(name)` gives the kind from the extension (the table of kinds above), never from the content. The board's public item carries it as `render`.
- `Channel.view` gives a `renders` address (a `ViewTokens` token with purpose `:render`) for each drawable item no larger than `RENDER_LIMIT`. `AssetServer#serve_render` checks the token as for `:view`, refuses a file over the limit before reading it (413) and bytes that are not UTF-8 (415), and serves the whole text as `text/plain` with `default-src 'none'`. It does not change what `note_text` recorded for the text view.
- `WorkerPolicy` (`lib/monadic/workbench/worker_policy.rb`) serves the Vega worker with `content-security-policy: default-src 'none'`.

## Page

`public/js/monadic/workbench-render.js` (`WorkbenchRender.draw(box, kind, text)`):

- Markdown: its own markdown-it (`html: false`) and its own DOMPurify instance (the chat's is not changed). No math. A Mermaid block becomes a diagram once its image is drawn, and stays as code otherwise. Images stay only as `data:` images of image types; links only `http(s)`/`mailto`, opened with `noopener noreferrer`.
- HTML: an allowlist of tags and attributes (no `a`, `area`, `svg`, `math`, form controls, frames, media, `meta`, `link`, `base`), CSS that could load something dropped, then a document the page builds with the policy meta first, in an `iframe` with `sandbox=""` given as the `srcdoc` property.
- SVG, diagrams and charts are shown as a Blob `<img>`; the URL is revoked with the drawing.
- Mermaid runs in a hidden `iframe sandbox="allow-scripts"`, within one time limit for reading the library, making the frame and drawing (a frame that does not answer is dropped) whose policy loads nothing; the library is read from `/vendor/js/mermaid.min.js` only (no CDN) and inlined. Text goes in by `postMessage` only; the frame turns the SVG into XML with a size from its `viewBox`. Settings inside a diagram (`%%{`, front matter) are refused before drawing; which kinds of diagram there are is Mermaid's to say, in the frame.
- Vega-Lite runs in a module worker built from `scripts/vega/` by `npm run build:vega` (`public/vendor/vega/`: `vega-worker.mjs`, `LICENSES.txt`; both are checked against a rebuild when the app is packaged, `scripts/build_products.rb`). `vega_worker_core.mjs` checks the spec (inline values only, listed transforms with their own keys, no `signal`, one fold and one pivot, facets on plain fields only, a view and row estimate, expressions wherever they appear read with Vega's own parser against a small grammar), compiles it, checks the compiled spec, and draws it to SVG with the expression interpreter and a loader that loads nothing. The page ends the worker after `CHART_WAIT_MS`.

`workbench.js` shows a drawable item with a **Drawn** / **Source** switch (kept per item version, with the vertical scroll position of each one's outer area; a table's own horizontal scroll and a page inside its frame are not kept). A drawing that fails says why and offers **Source**; a file over `RENDER_LIMIT` as it is now is refused before it is read (`FileItem.read(limit:)`). While it is drawn, the capture answer for the lines in view is `rendered`; `look_at_workbench` then refuses `visible` and marks a `whole` result as `source_text`.

## Writing and recording

- `put_on_workbench` (`MonadicSharedTools::WorkbenchTools`, `Monadic::Workbench::Put`) writes a new file under the chat folder's `workbench/`. The write is decided under the epoch lock (`Chats.admit_in_epoch`) with `ReplyHandle#admit_write`, inside `Thread.handle_interrupt(Object => :never)` until the file is linked in place (`SharedFs.write_new`, whose temporary names `SharedFolder.list` leaves out).
- `Monadic::Workbench::Shown` collects what a running reply showed (put and show); `html_handler.rb` seals it into the message's `workbench_shown` before sending it; `finish_reply` closes it. `Shown.clean` is the form kept by the history, the export and the import. A line from the record opens that version through `WORKBENCH_OPEN` with `sha256` (`Board#add_file(sha256:)`).

## Tests

- `spec/unit/workbench/files_spec.rb` (render address), `put_spec.rb`, `reply_wiring_spec.rb`, `worker_policy_spec.rb`, `look_spec.rb`, `look_capture_spec.rb`
- `spec/unit/render_formats_spec.rb`, `test/frontend/render-registry.test.js` (the table and the chat's diagrams)
- `test/frontend/workbench-render.test.js`, `workbench.test.js`, `workbench-render-browser.test.js` (a real browser; every address a drawn file names points at the test server, which counts what reaches it)
