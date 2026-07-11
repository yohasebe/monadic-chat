# FAQ: Media Files

##### Q: Can I send data other than text to the AI agent? :id=sending-non-text-data

**A**: Yes, if the selected model supports it, you can upload images (JPG, JPEG, PNG, GIF, WebP) by clicking the `Image` button. You can also upload multiple images by repeating this process. If you are using models from Anthropic Claude, OpenAI, or Google Gemini that support vision capabilities, the same button will also allow you to upload PDF files.

For other media, place the file in the shared folder and specify the file name (no path required) in the message box to inform the AI agent. If the selected app supports it, the AI agent will read and process the file.

The following basic apps support file reading:

- Code Interpreter<br />Various text files including Python scripts and CSV, Microsoft Office files, audio files (MP3, WAV, M4A, and other common formats)
- Knowledge Base<br />Imports PDFs, Microsoft Office files (.docx / .xlsx / .pptx), Markdown, and source-code files via the Browse modal's **Import file** button
- Video Description<br />Video files (MP4, MOV, AVI, MKV, and other common formats)

You can also click the `Speech Input` button to use voice input. Speech input uses the Speech-to-Text API and is available in all apps.

---

##### Q: Can I ask the AI agent about the contents of a PDF? :id=pdf-content-questions

**A**: Yes, there are several ways to do this. In the [`Knowledge Base`](../apps/knowledge-base.md) app you can use **Import file** to ingest the PDF into the project-wide vector database and have the AI answer using RAG (Retrieval-Augmented Generation). In the [`Code Interpreter`](../apps/coding-apps.md#code-interpreter) app you can also convert the PDF to Markdown programmatically and have the AI agent read the content so you can ask questions about it.

In apps that use vision-capable models from Anthropic Claude, OpenAI, or Google Gemini, you can click the `Image` button below the text input box to upload a PDF file directly and ask the AI agent about its contents. The button dynamically allows PDF uploads when using models that support this feature. For more information, see [Uploading PDFs](../basic-usage/message-input.md#uploading-pdfs).

