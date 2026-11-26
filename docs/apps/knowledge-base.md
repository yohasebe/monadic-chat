# Library :id=knowledge-base

Keep conversations and documents in one searchable library.

The Library holds conversations and documents: conversation transcripts, PDFs, Office files, Markdown, and source code. The **Library** tab of the sidebar shows all of it, and every app that searches the Library searches all of it.

**Ways to add content:**

1. **Keep this conversation as a document**: **Keep this conversation** in the **Library** tab puts the conversation on the work screen as a Markdown document: the title, the app, the model and the date, then each turn under a heading. Files of the conversation are named, not kept; system prompts, thinking and tool records are left out. Check it there, and keep it with **Keep in the Library**, giving it a title (its first heading is offered). When a record of the same conversation is kept already, you choose to update that record or keep this one as another document. Apps whose conversations are not kept in the Library (such as the image and diagram generators) do not offer this.
2. **Keep a document of the work screen**: under a document on the [work screen](../basic-usage/web-interface.md#work-screen) in one of the formats below, **Keep in the Library** imports it as the version shown.
3. **Import a file**: open the **Library** tab of the sidebar and click **Import file** to upload a file in one of the formats below. The file is extracted, split into sections, and stored as one entry that you can search, view, and rename. The file itself is kept in `~/monadic/library`, outside the shared folder; it is deleted with its entry, unless another entry was made from the same file.

**Supported import formats:**

| Format | Extensions |
|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` |
| Source code | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql`, and others |
| PDF | `.pdf` |
| Office | `.docx`, `.xlsx`, `.pptx` |

The text and tables of PDFs are extracted. With the Library Quality Pack installed, layout analysis and OCR are used; without it, no text is extracted from image-only PDFs.

A chat that [hides words](../advanced-topics/anonymization.md) cannot be kept, but it can still search the Library.

**Other features:**

- **Rename**: open the Conversation Viewer, click the pencil icon next to the title, edit, and save.
- **Search and counts**: the Library tab shows how many entries there are, and can be searched and sorted.
- **Open on the work screen**: the first button of a row in the Library tab puts the entry on the [work screen](../basic-usage/web-interface.md#work-screen): a PDF as its kept file, Markdown and source code as the kept file's text, other entries (Office documents, saved conversations) as their text. The AI reads it as any other item: what the conversation needs, and the whole when the question needs it (with a model that takes files, a PDF or Office document as it is). If the entry changes or is deleted in the Library, the work screen says so.
- **Conversation Viewer**: click a row to see every message of the entry. The system prompt is folded.
- **Open the original chat**: a conversation kept as a document has a button in its row that opens the chat it was made from, while that chat is in the history.
- **Retrieval in chats**: the AI searches the Library when you ask it to, when you refer to what you keep there, or when it clearly helps with the question; it does not search on every turn, and it can list what the Library holds. The passages it read are put on the [work screen](../basic-usage/web-interface.md#work-screen) and listed under its reply, with how many it cited; a passage it cites opens from its link in the reply, as it was read even when the entry has changed since. To keep the AI from using the Library, turn off **The Library, in chats** under **Sources the AI can use** in the General section of Settings; the change takes effect when Monadic Chat starts again. In Live Conversation the AI searches only while the app's **Search and compute** switch is on.

?> The Library converts text into vectors on your computer and stores them in Qdrant, so importing and searching need no API key. See [Vector Database](../docker-integration/vector-database.md).
