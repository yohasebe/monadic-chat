# FAQ: Media Files

##### Q: Can I send data other than text to the AI agent? :id=sending-non-text-data

**A**: Yes. Put the files on the [work screen](../basic-usage/web-interface.md#work-screen) (images, PDFs, documents, audio, video): the AI looks at them when your question needs it, with a model that reads images. See [Files for the AI](../basic-usage/message-input.md#files-for-the-ai).

For other media, place the file in the shared folder and specify the file name (no path required) in the message box to inform the AI agent. If the selected app supports it, the AI agent will read and process the file.

The following basic apps support file reading:

- Code Interpreter<br />Text files including Python scripts and CSV, PDF and Microsoft Office files; other files, such as audio, through Python code
- Library<br />Imports PDFs, Microsoft Office files (.docx / .xlsx / .pptx), Markdown, and source-code files via the **Import file** button of the **Library** tab
- Video Describer<br />Video files (MP4, M4V, MOV, WebM, MKV, AVI)

You can also click the `Speech Input` button to use voice input. Speech input uses the Speech-to-Text API and is available in all apps.

---

##### Q: Can I ask the AI agent about the contents of a PDF? :id=pdf-content-questions

**A**: Yes, there are several ways to do this. In the **Library** tab of the sidebar ([Library](../apps/knowledge-base.md)) you can use **Import file** to ingest the PDF into the project-wide vector database, and an app that searches the Library answers using RAG (Retrieval-Augmented Generation). In the [`Code Interpreter`](../apps/coding-apps.md#code-interpreter) app you can also convert the PDF to Markdown programmatically and have the AI agent read the content so you can ask questions about it.

You can also put a PDF on the [work screen](../basic-usage/web-interface.md#work-screen) and ask the AI agent about its contents: the AI reads its text, and with Anthropic Claude, OpenAI and Google Gemini models that read PDFs, it is given the whole PDF as it is. For more information, see [Files for the AI](../basic-usage/message-input.md#files-for-the-ai).

