# Drawing text files in the work screen

The work screen draws some text files of the shared folder: Markdown, Mermaid diagrams, CSV/TSV tables, SVG, static HTML pages and Vega-Lite charts. The server only names the kind and serves text; the page draws. Nothing drawn may reach the network or run as script.

## Server

- `SharedFolderPreview.render_for(name)` (`lib/monadic/workspace/shared_folder_preview.rb`) gives the kind from the extension (`RENDER`, `RENDER_COMPOUND` for `.vl.json`), never from the content. The board's public item carries it as `render`.
- `Channel.view` gives a `renders` address (a `ViewTokens` token with purpose `:render`) for each drawable item no larger than `RENDER_LIMIT`. `AssetServer#serve_render` checks the token as for `:view`, refuses a file over the limit before reading it (413) and bytes that are not UTF-8 (415), and serves the whole text as `text/plain` with `default-src 'none'`. It does not change what `note_text` recorded for the text view.
- `WorkerPolicy` (`lib/monadic/workbench/worker_policy.rb`) serves the Vega worker with `content-security-policy: default-src 'none'`.

## Page

`public/js/monadic/workbench-render.js` (`WorkbenchRender.draw(box, kind, text)`):

- Markdown: its own markdown-it (`html: false`) and its own DOMPurify instance (the chat's is not changed). No math. A Mermaid block becomes a diagram once its image is drawn, and stays as code otherwise. Images stay only as `data:` images of image types; links only `http(s)`/`mailto`, opened with `noopener noreferrer`.
- HTML: an allowlist of tags and attributes (no `a`, `area`, `svg`, `math`, form controls, frames, media, `meta`, `link`, `base`), CSS that could load something dropped, then a document the page builds with the policy meta first, in an `iframe` with `sandbox=""` given as the `srcdoc` property.
- SVG, diagrams and charts are shown as a Blob `<img>`; the URL is revoked with the drawing.
- Mermaid runs in a hidden `iframe sandbox="allow-scripts"`, within one time limit for reading the library, making the frame and drawing (a frame that does not answer is dropped) whose policy loads nothing; the library is read from `/vendor/js/mermaid.min.js` only (no CDN) and inlined. Text goes in by `postMessage` only; the frame turns the SVG into XML with a size from its `viewBox`. Settings inside a diagram (`%%{`, front matter) and unlisted diagram types are refused before drawing.
- Vega-Lite runs in a module worker built from `scripts/vega/` by `npm run build:vega` (`public/vendor/vega/`: `vega-worker.mjs`, `LICENSES.txt`; both are checked against a rebuild when the app is packaged, `scripts/build_products.rb`). `vega_worker_core.mjs` checks the spec (inline values only, listed transforms with their own keys, no `signal`, one fold and one pivot, facets on plain fields only, a view and row estimate, expressions wherever they appear read with Vega's own parser against a small grammar), compiles it, checks the compiled spec, and draws it to SVG with the expression interpreter and a loader that loads nothing. The page ends the worker after `CHART_WAIT_MS`.

`workbench.js` shows a drawable item with a **Drawn** / **Source** switch (kept per item version, with the vertical scroll position of each one's outer area; a table's own horizontal scroll and a page inside its frame are not kept). A drawing that fails says why and offers **Source**; a file over `RENDER_LIMIT` as it is now is refused before it is read (`FileItem.read(limit:)`). While it is drawn, the capture answer for the lines in view is `rendered`; `look_at_workbench` then refuses `visible` and marks a `whole` result as `source_text`.

## Writing and recording

- `put_on_workbench` (`MonadicSharedTools::WorkbenchTools`, `Monadic::Workbench::Put`) writes a new file under the chat folder's `workbench/`. The write is decided under the epoch lock (`Chats.admit_in_epoch`) with `ReplyHandle#admit_write`, inside `Thread.handle_interrupt(Object => :never)` until the file is linked in place (`SharedFs.write_new`, whose temporary names `SharedFolder.list` leaves out).
- `Monadic::Workbench::Shown` collects what a running reply showed (put and show); `html_handler.rb` seals it into the message's `workbench_shown` before sending it; `finish_reply` closes it. `Shown.clean` is the form kept by the history, the export and the import. A line from the record opens that version through `WORKBENCH_OPEN` with `sha256` (`Board#add_file(sha256:)`).

## Tests

- `spec/unit/workbench/files_spec.rb` (render address), `put_spec.rb`, `reply_wiring_spec.rb`, `worker_policy_spec.rb`, `look_spec.rb`, `look_capture_spec.rb`
- `test/frontend/workbench-render.test.js`, `workbench.test.js`, `workbench-render-browser.test.js` (a real browser; every address a drawn file names points at the test server, which counts what reaches it)
