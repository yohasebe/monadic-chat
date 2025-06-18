# FAQ: Media Files

**Q**: Can I send data other than text to the AI agent? :id=sending-non-text-data

**A**: Yes, if the selected model supports it, you can upload images (JPG, JPEG, PNG, GIF, WebP) by clicking the `Image` button. You can also upload multiple images by repeating this process. If you are using models from Anthropic Claude, OpenAI, or Google Gemini that support vision capabilities, the same button will also allow you to upload PDF files.

For other media, place the file in the shared folder and specify the file name (no path required) in the message box to inform the AI agent. If the selected app supports it, the AI agent will read and process the file.

The following basic apps support file reading:

- Code Interpreter<br />Various text files including Python scripts and CSV, Microsoft Office files, audio files (MP3, WAV, M4A, and other common formats)
- Content Reader<br />Text files, PDF files, Microsoft Office files, audio files (MP3, WAV, M4A, and other common formats)
- PDF Reader<br />PDF files
- Video Description<br />Video files (MP4, MOV, AVI, MKV, and other common formats)

You can also click the `Speech Input` button to use voice input. Speech input uses the Speech-to-Text API and is available in all apps.

---

**Q**: Can I ask the AI agent about the contents of a PDF? :id=pdf-content-questions

**A**: Yes, there are several ways to do this. In the [`PDF Navigator`](../basic-usage/basic-apps.md#pdf-navigator) app, you can store the word embeddings of the provided PDF in the PGVector database and have the AI answer using the RAG (Retrieval-Augmented Generation) method. In the [`Code Interpreter`](../basic-usage/basic-apps.md#code-interpreter) and [`Content Reader`](../basic-usage/basic-apps.md#content-reader) apps, you can convert the PDF file to Markdown format using MuPDF4LLM on the Python container and have the AI agent read the content so you can ask questions about it.

All of the above use OpenAI models by default. If you use other providers, you can load PDF files in the same way as the `Code Interpreter` in apps that support `Code` functionality.

In apps that use vision-capable models from Anthropic Claude, OpenAI, or Google Gemini, you can click the `Image` button below the text input box to upload a PDF file directly and ask the AI agent about its contents. The button dynamically allows PDF uploads when using models that support this feature. For more information, see [Uploading PDFs](../basic-usage/message-input.md#uploading-pdfs).

