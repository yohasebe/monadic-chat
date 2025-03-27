# FAQ: User Interface

**Q**: Please explain the roles of the buttons and icons at the top right of each message on the web interface.

**A**: The roles of each button and icon are as follows:

![](../assets/images/message-buttons.png ':size=600')

- **Copy**<br />Copies the message text to the clipboard.
- **Play**<br />Plays the message text using speech synthesis.
- **Stop**<br />Stops playback of synthesized speech.
- **Delete**<br />Opens a dialog with options to either "Delete this message and below", "Delete this message only", or "Cancel". The first option deletes the selected message and all messages that appear after it in the conversation, which can be useful in certain cases but should be used with caution. The "Delete this message only" option should also be used carefully, as it may disrupt the alternating user-assistant message pattern required by some API providers (like Perplexity), which can lead to API errors. Note: If the message is the last assistant or system message in the conversation, only "Delete this message only" and "Cancel" options will be shown.
- **Edit**<br />Allows editing the message. For most messages, clicking this button displays an inline text editor directly in the chat interface with "Save" and "Cancel" buttons. However, if the message is the last message in the conversation (regardless of role), clicking Edit will automatically move that text to the main message input area, set the appropriate role in the selector, and remove the original message, allowing you to quickly revise and resend it. For other messages, the edited message maintains its original position in the conversation, and subsequent messages are preserved.
- **Active/Inactive**<br />The message turns green when active.

The active/inactive status of a message changes depending on the context size and maximum token settings on the web interface. Active messages are used as part of the context sent to the LLM via the API.

---

**Q**: How is the number of tokens displayed in Monadic Chat Stats calculated?

**A**: It is calculated using [tiktoken](https://github.com/openai/tiktoken) installed on the Python container.  Regardless of the selected model, the `cl100k_base` encoding is used, so the value may not always be accurate if a model other than the GPT-4 series is selected. Consider the token count as an approximate value.

---

**Q**: What is the role of the `Role` selector above the message input box?

**A**: Each role has the following function:

![](../assets/images/role-selector.png ':size=400')

- **User**<br />Normally select this. Enter a message as a user and immediately send it to the AI agent for a response.
- **User (to add to past messages)**<br />Enter a message as a user, but use it to add to past messages as part of the context. Do not request a direct response from the AI agent.
- **Assistant (to add to past messages)**<br />Add text as a message from the AI assistant. Use it to add to past messages as part of the context.
- **System (to provide additional direction)**<br />Use this to provide additional system prompts.

---

**A**: When I access localhost:4567 in the browser, it shows "Not Secure". Is this a security concern?

**Q**: This application is secure because the server only accepts connections from `localhost` (`127.0.0.1`). The "Not Secure" warning shown in your browser is not a concern for this local connection.
