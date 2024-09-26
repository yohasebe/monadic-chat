# Frequently Asked Questions

---

**Q**: Do I need an OpenAI API token to use Monadic Chat?

**A**: Yes, an OpenAI API token is required not only for AI chat but also for speech recognition, speech synthesis, and creating text embeddings. Even if you primarily use APIs other than OpenAI for chat, such as Anthropic's Claude, an OpenAI API token is still necessary.

---

**Q**: Rebuilding Monadic Chat (rebuilding the containers) fails. What should I do?

**A**: If you are developing additional apps or modifying existing apps, check the contents of `monadic.log` in the shared folder. If an error message is displayed, correct the app code based on the error message.  If you are not developing or modifying apps and no error message is displayed in the log, temporarily move the subfolders (`apps`, `services`, etc.) of the shared folder to another location and rebuild.

---

**Q**: I installed the Ollama plugin and downloaded a model, but it is not reflected in the web interface. What should I do?

**A**: It may take some time for the model downloaded to the Ollama container to be loaded and become available. Wait a while and then reload the web interface. If the downloaded model still does not appear, access the Ollama container from the terminal and run the `ollama list` command to check if the downloaded model is displayed in the list. If it is not displayed, run the `ollama reload` command to reload the Ollama plugin.


---

**Q**: Please explain the roles of the buttons and icons at the top right of each message on the web interface.

**A**: The roles of each button and icon are as follows:

![](/assets/images/message-buttons.png ':size=600')

- **Copy**<br />Copies the message text to the clipboard.
- **Play**<br />Plays the message text using speech synthesis.
- **Stop**<br />Stops playback of synthesized speech.
- **Delete**<br />Deletes the message.
- **Edit**<br />Edits the message.
- **Active/Inactive**<br />The message turns green when active.

The active/inactive status of a message changes depending on the context size and maximum token settings on the web interface. Active messages are used as part of the context sent to the LLM via the API.

---

**Q**: How is the number of tokens displayed in Monadic Chat Stats calculated?

**A**: It is calculated using [tiktoken](https://github.com/openai/tiktoken) installed on the Python container.  Regardless of the selected model, the `cl100k_base` encoding is used, so the value may not always be accurate if a model other than the GPT-4 series is selected. Consider the token count as an approximate value.

---

**Q**: Sometimes the text is played back in a different language than the actual language during speech synthesis. What should I do?

**A**: The `Automatic-Speech-Recognition (ASR) Language` selector on the web interface is set to `Automatic` by default. By setting it to a specific language, the text will be played back in the specified language during speech synthesis.

---

**Q**: What is the role of the `Role` selector above the message input box?

**A**: Each role has the following function:

![](/assets/images/role-selector.png ':size=400')

- **User**<br />Normally select this. Enter a message as a user and immediately send it to the AI agent for a response.
- **User (to add to past messages)**<br />Enter a message as a user, but use it to add to past messages as part of the context. Do not request a direct response from the AI agent.
- **Assistant (to add to past messages)**<br />Add text as a message from the AI assistant. Use it to add to past messages as part of the context.
- **System (to provide additional direction)**<br />Use this to provide additional system prompts.

---

**Q**: Can I send data other than text to the AI agent?

**A**: Yes, if the selected model supports it, you can upload images by clicking the `Use Image` button. You can also upload multiple images by repeating this process.

For other media, place the file in the shared folder and specify the file name (no path required) in the message box to inform the AI agent. If the selected app supports it, the AI agent will read and process the file.

The following basic apps support file reading:

- Code Interpreter<br />Various text files including Python scripts and CSV, Microsoft Office files, audio files (MP3, WAV)
- Content Reader<br />Text files, PDF files, Microsoft Office files, audio files (MP3, WAV)
- PDF Reader<br />PDF files
- Video Description<br />Video files (MP4, MOV)

You can also click the `Voice Input` button to use voice input. Voice input uses the Whisper API and is available in all apps.

---

**Q**: Can I save the input text as an MP3 file by synthesizing speech?

**A**: Yes, you can save the synthesized speech as a file by selecting the `Speech Draft Helper` app, entering the text, and instructing the AI agent to convert it to an MP3 file.

---

**Q**: Can I have a voice conversation with the AI agent?

**A**: Yes, you can. Enable both `Auto speech` and `Easy submit` in the `Chat Interaction Controls` on the web interface. You can start and complete voice message input by pressing the Enter key (without clicking a button). Also, when the input is complete, the message is automatically sent, and the synthesized voice of the response from the AI agent is played. In other words, you can have a voice conversation with the AI agent just by pressing the Enter key at the right time.
