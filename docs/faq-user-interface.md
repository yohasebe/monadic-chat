# FAQ: User Interface

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

**Q**: What is the role of the `Role` selector above the message input box?

**A**: Each role has the following function:

![](/assets/images/role-selector.png ':size=400')

- **User**<br />Normally select this. Enter a message as a user and immediately send it to the AI agent for a response.
- **User (to add to past messages)**<br />Enter a message as a user, but use it to add to past messages as part of the context. Do not request a direct response from the AI agent.
- **Assistant (to add to past messages)**<br />Add text as a message from the AI assistant. Use it to add to past messages as part of the context.
- **System (to provide additional direction)**<br />Use this to provide additional system prompts.

