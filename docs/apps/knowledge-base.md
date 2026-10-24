# Knowledge Base

Save chat sessions and import documents into one searchable library.

The Knowledge Base holds conversations and documents: conversation transcripts, PDFs, Office files, Markdown, and source code. The Knowledge Base browser shows all of it, and apps can search it as described under the scope model below.

?> The Knowledge Base is separate from the [PDF Database](../basic-usage/pdf_storage.md), which stores PDFs for the OpenAI versions of Chat Plus and Research Assistant. Content imported into one is not visible in the other.

**Two ways to add content:**

1. **Save the current chat session**: the **Save** button in the Knowledge Base panel of the sidebar saves the current conversation to the Knowledge Base.
2. **Import a file**: open the Knowledge Base browser (**Browse**) and click **Import file** to upload a file in one of the formats below. The file is extracted, split into sections, and stored as one entry that you can search, view, and rename.

**Supported import formats:**

| Format | Extensions |
|---|---|
| Markdown | `.md`, `.markdown`, `.mdx` |
| Source code | `.rb`, `.py`, `.js` / `.ts`, `.go`, `.java`, `.kt`, `.swift`, `.rs`, `.c` / `.cpp`, `.cs`, `.php`, `.sh`, `.sql`, and others |
| PDF | `.pdf` |
| Office | `.docx`, `.xlsx`, `.pptx` |

The text and tables of PDFs are extracted. With the Knowledge Base Quality Pack installed, layout analysis and OCR are used; without it, no text is extracted from image-only PDFs.

Apps that use the Privacy Filter (such as Translate and Mail Composer) do not save to or search the Knowledge Base, and some other apps do not either; in those apps the Save button and the retrieval switch are not available.

**Scope model:**

Each entry belongs either to the app and provider it was saved in (for example `Chat (OpenAI)`) or to `Global`. When an app searches the Knowledge Base, an app-only entry is found only from the same app and provider: `Chat (OpenAI)` does not find entries saved in `Chat (Claude)`, and the reverse. `Global` entries are found from every app that searches the Knowledge Base. Click the rotate icon in the Browse table, or **Make Global** / **Make app-only** in the Conversation Viewer, to switch between the two.

**Other features:**

- **Saving again updates the entry**: saving the same chat session again updates its entry instead of creating another one. The dialog then reads "Update Conversation in Knowledge Base", with an **Update** button and a note. The link between the session and the entry ends on Reset, on switching apps, or when the entry is deleted in Browse.
- **Suggested titles**: when you first save a conversation, the title field is filled in by the current provider's model, based on the conversation. You can type over it. The suggestion is kept, so closing and reopening the dialog does not ask the model again.
- **Rename**: open the Conversation Viewer, click the pencil icon next to the title, edit, and save.
- **Recent saves and counts**: the sidebar shows the most recent saves and the total counts. The Browse table can be searched, filtered by scope, and sorted.
- **Conversation Viewer**: click a row to see every message of the entry. The system prompt is folded.
- **Retrieval in apps**: turn on **Use Knowledge Base for retrieval (this session)** in the Knowledge Base panel to let the model search the Knowledge Base while answering. It finds the entries of the current app and the `Global` entries. The switch is off by default, and your last choice is remembered. Live Conversation uses its own **Tools** switch instead.
- **Knowledge Base badge**: the conversation header shows a green "Knowledge Base" badge while the retrieval switch is on and the session can read from the Knowledge Base.

?> The Knowledge Base converts text into vectors on your computer and stores them in Qdrant, so importing and searching need no API key. See [Vector Database](../docker-integration/vector-database.md).
