# FAQ: Media Files

**Q**: Can I send data other than text to the AI agent?

**A**: Yes, if the selected model supports it, you can upload images by clicking the `Use Image` button. You can also upload multiple images by repeating this process. If you are using Anthropic Claude, you can upload PDF files in addition to images.

For other media, place the file in the shared folder and specify the file name (no path required) in the message box to inform the AI agent. If the selected app supports it, the AI agent will read and process the file.

The following basic apps support file reading:

- Code Interpreter<br />Various text files including Python scripts and CSV, Microsoft Office files, audio files (MP3, WAV)
- Content Reader<br />Text files, PDF files, Microsoft Office files, audio files (MP3, WAV)
- PDF Reader<br />PDF files
- Video Description<br />Video files (MP4, MOV)

You can also click the `Speech Input` button to use voice input. Speech input uses the Whisper API and is available in all apps.

---

**Q**: Can I ask the AI agent about the contents of a PDF?

**A**: Yes, there are several ways to do this. In the [`PDF Navigator`](./basic-apps?id=pdf-navigator) app, you can store the word embeddings of the provided PDF in the PGVector database and have the AI answer using the RAG (Retrieval-Augmented Generation) method. In the [`Code Interpreter`](./basic-apps?id=code-interpreter) and [`Content Reader`](./basic-apps?id=content-reader) apps, you can convert the PDF file to Markdown format using MuPDF4LLM on the Python container and have the AI agent read the content so you can ask questions about it.

All of the above use OpenAI's GPT-4 series models. If you use other models, you can load PDF files in the same way as the `Code Interpreter` in apps that support `Code` (`Anthropic Claude [Code]`, `Cohere Command R [Code]`, and `Mistral AI [Code]`).

In apps that use Anthropic Claude, you can click the `Import Image/PDF` button below the text input box to upload a PDF file directly and ask the AI agent about its contents. For more information, see [Uploading PDFs](./message-input?id=uploading-pdfs).

