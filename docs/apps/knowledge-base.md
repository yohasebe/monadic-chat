# Knowledge Base

Save chat sessions and import documents into a single searchable library that any app can retrieve from.

A unified, project-wide library of conversations and documents. The Knowledge Base is shared across every Monadic Chat app, so anything you save here can be retrieved later from any chat session.

The Knowledge Base replaces the previous PDF Navigator and Content Reader apps. Their functionality is consolidated into a single subsystem that handles conversation transcripts, PDFs, Office files, Markdown, and source code uniformly.

?> The Knowledge Base is separate from the per-app [PDF Database panel](../basic-usage/pdf_storage.md), which serves app-scoped PDF storage for apps that declare `pdf_vector_storage` (currently Chat Plus and Research Assistant). Content imported into one is not visible in the other.

**Two ways to add content:**

1. **Save the current chat session** — the **Save** button in the sidebar serialises the active conversation (messages + participants + metadata) into the Knowledge Base.
2. **Import a file** — open the Knowledge Base Browser and click **Import file** to upload one of the supported formats below. The file is extracted, chunked, embedded, and stored as a single conversation entry that you can search, view, and rename.

**Supported import formats:**

| Format | Extensions | Notes |
|---|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` | YAML frontmatter is promoted into metadata; ATX headings drive section boundaries. |
| Source code | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql`, and others | Top-level `def`/`class`/`func`/etc. mark chunk boundaries. The programming language is recorded as a topic. |
| PDF | `.pdf` | Text and tables are extracted and serialised as Markdown — with layout-aware extraction and OCR when the Knowledge Base Quality Pack is installed. PDF metadata title becomes the conversation title. |
| Office | `.docx`, `.xlsx`, `.pptx` | Word paragraphs, Excel sheets, and PowerPoint slides each become a chunk. The Browse modal shows a per-format icon (Word / Excel / PowerPoint). |

**Scope model:**

Each entry is scoped either to a specific app + provider (e.g. `Chat (OpenAI)`) or to `Global`. App-only entries are retrievable only from the same app + provider combination — `Chat (OpenAI)` cannot see entries saved while `Chat (Claude)` was active, and vice versa. `Global` entries are retrievable from every app via the `library_search` tool. Click the rotate icon in the Browse table or the **Make Global / Make app-only** button in the Conversation Viewer to flip between the two.

**Other features:**

- **Save replaces in place** — saving the same chat session a second time updates the existing entry instead of creating a duplicate. The modal switches to "Update Conversation in Knowledge Base" mode (with an "Update" button and a warning banner) when re-saving. The binding clears on Reset, app switch, or when the entry is deleted from Browse.
- **AI-suggested titles** — on first save the title field is auto-populated by your current provider's LLM, using the first few turns of the conversation. The suggestion is a default — type freely to override it. Suggestions are cached so canceling and re-opening the dialog does not re-run the model.
- **Rename** — open the Conversation Viewer, click the pencil icon next to the title, edit, and save. The Browse table updates immediately.
- **Inventory and stats** — the sidebar shows the most recent saves and total counts. The Browse modal supports search, filtering by scope, and sorting.
- **Conversation Viewer** — clicking a row opens a verbatim playback of every message, with system prompts collapsed behind a `<details>` block.
- **RAG opt-in (per session)** — the **Use Knowledge Base for retrieval** toggle in any chat session lets the LLM call `library_search` while answering. The cascade applies the active app's scope filter (`scope_app IN [current_app, "Global"]`). Off by default; locks for the duration of the session once you send the first message. The toggle preference is persisted across sessions so you don't have to flip it every time.
- **Privacy Filter compatibility** — when Privacy Filter is active, snippets returned by `library_search` are masked through the same Privacy Pipeline before they reach the LLM, so PII stored unmasked in the Knowledge Base does not leak via retrieval.
- **Knowledge Base access badge** — the conversation header shows a green "Knowledge Base" badge whenever the session reads from the Library: when the retrieval toggle is on, and always in the Knowledge Base app itself (which has full access via its own tools).

?> The Knowledge Base uses local embeddings (`multilingual-e5-base`) and a Qdrant vector store — no external API key is needed for import or search. For the extraction, chunking, and storage internals, see the [Vector Database](../docker-integration/vector-database.md) documentation.
