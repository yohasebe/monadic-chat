# Writing & Document Apps

Apps that help you draft and produce written content — from novels and emails to speeches and Office documents.

## Novel Writer

![Novel Writer app icon](../assets/icons/novel-writer.png ':size=40')

Co-write a novel with the assistant. The assistant first asks for the genre, the language of the story, its approximate length, and any characters or settings you have in mind. It then writes the story one section at a time, following your directions, and offers options for what comes next. The characters, plot, and settings are kept in the side panel.


## Mail Composer

![Mail Composer app icon](../assets/icons/mail-composer.png ':size=40')

Draft emails with the assistant. It first asks what kind of email you want, then drafts it from your requests. Mail Composer has web search and uses the Privacy Filter.


Mail Composer supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Speech Draft Helper

![Speech Draft Helper app icon](../assets/icons/speech-draft-helper.png ':size=40')

Draft speeches with the assistant. Ask it to write a speech on a topic, or give it a draft (as plain text, a Word document, or a PDF) to improve. The speech can be saved as an audio file: MP3 with OpenAI and ElevenLabs voices, and the format the API returns (usually WAV) with Gemini voices.

A recording of a speech can be transcribed as well: attach an audio file with the attach button below the message box (`Attach file` or `Image`, depending on the model) (MP3, M4A, WAV, OGG, Opus, FLAC, WebM or AAC), or name a file placed in the shared folder. The speech in the recording is found first and transcribed segment by segment, so each line of the transcript starts with the time in the recording of the speech it holds (for example `[01:02–01:06]`). Recordings up to 50 minutes are transcribed; the 25 MB limit of transcribing a whole file at once does not apply (an attached file can be up to 2 GB). The transcript is saved as `transcript.json` in the chat's folder (`conversations/` in the shared folder), with WebVTT and SRT subtitle files. Timed transcripts need an up-to-date Python container. If the container is older than the app, the recording is transcribed without times (up to 25 MB), with a note to rebuild the container with **Actions → Build Python Container**.


## Document Generator :id=document-generator

![Document Generator app icon](../assets/icons/document-generator.png ':size=40')

Generate Excel spreadsheets, PowerPoint presentations, Word documents, and PDFs. The files are saved in the `documents` folder of the shared folder.

**Key Features:**
- **Excel (.xlsx)**: Data tables, charts, formulas, multiple sheets
- **PowerPoint (.pptx)**: Slides with layouts
- **Word (.docx)**: Documents with headings, lists, and tables
- **PDF**: Formatted documents

Document Generator has web search. It is available for Claude and needs an Anthropic API key.
