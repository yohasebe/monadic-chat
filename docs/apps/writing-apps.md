# Writing & Document Apps

Apps that help you draft and produce written content — from novels and emails to speeches and Office documents.

## Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

Co-write a novel with the assistant. The story unfolds based on your prompts, maintaining consistency and flow. The AI will first ask for the story's setting, characters, and genre. You can then provide prompts to guide the AI as it continues the story.


## Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

Draft emails in collaboration with the assistant. The AI will draft emails based on your requests and specifications.


Mail Composer supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

Draft speeches with the help of an AI assistant. You can ask the assistant to write a speech on a specific topic, or provide an existing draft (as plain text, a Word document, or a PDF) for it to improve. The final speech can be exported as an audio file in a format supported by your text-to-speech provider (e.g., MP3 or WAV).

A recording of a speech can be transcribed as well: attach an audio file with the `Image` button below the message box (MP3, M4A, WAV, OGG, Opus, FLAC, WebM or AAC), or name a file placed in the shared folder. The speech in the recording is found first and transcribed segment by segment, so each line of the transcript starts with the time in the recording of the speech it holds (for example `[01:02–01:06]`). Recordings up to 50 minutes are transcribed; the 25 MB limit of transcribing a whole file at once does not apply (an attached file can be up to 2 GB). The transcript is saved as `transcript.json` in the chat's folder (`conversations/` in the shared folder), with WebVTT and SRT subtitle files. Timed transcripts need a Python container built for this version; with an older one, the recording is transcribed without times (up to 25 MB) and a note says to rebuild the container.


## Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

Generate Office documents using AI, including Excel spreadsheets, PowerPoint presentations, Word documents, and PDFs. Files are automatically saved to your shared folder.

**Key Features:**
- **Excel (.xlsx)**: Data tables, charts, formulas, multiple sheets
- **PowerPoint (.pptx)**: Professional slides with visual layouts
- **Word (.docx)**: Formatted documents with headings, lists, tables
- **PDF**: Professional documents with proper formatting

Document Generator is currently available for Claude.
