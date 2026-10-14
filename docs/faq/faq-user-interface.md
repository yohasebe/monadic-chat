# FAQ: User Interface

##### Q: Please explain the roles of the buttons and icons at the top right of each message on the web interface. :id=message-buttons-explanation

**A**: The roles of each button and icon are as follows:

- **Copy**<br />Copies the message text to the clipboard.
- **Play**<br />Plays the message text using speech synthesis.
- **Stop**<br />Stops playback of synthesized speech.
- **Delete**<br />Opens a dialog with options to either `Delete this message and below`, `Delete this message only`, or `Cancel`. The first option deletes the selected message and all messages that appear after it in the conversation, which can be useful in certain cases but should be used with caution. The `Delete this message only` option should also be used carefully, as it may disrupt the alternating user-assistant message pattern required by some API providers, which can lead to API errors.

?> **Note**: For the last message in the conversation, only `Delete this message only` and `Cancel` are shown.
- **Edit**<br />Allows editing the message. For most messages, clicking this button displays an inline text editor directly in the chat interface with `Save` and `Cancel` buttons. If the message is your own last message, clicking `Edit` moves its text to the message box, sets the role selector, and removes the original message, so you can revise and resend it. Other messages, including assistant and system messages, are edited in place; they keep their position, and the messages after them are kept.
- **Verify**<br />On assistant messages, cross-checks the response with your other configured providers (with only one provider, it is a weaker self-consistency check).
- **Active/Inactive**<br />A small dot that is green when the message is active.

?> The active/inactive status of a message changes depending on the context size and maximum token settings on the web interface. Active messages are used as part of the context sent to the LLM via the API.

---

##### Q: How is the number of tokens displayed in Statistics calculated? :id=token-count-calculation

**A**: The **Statistics** section of the **AI Assistant & AI User** panel counts tokens with a local tokenizer. The displayed value is an approximation and may differ slightly from the count of the model in use.

---

##### Q: What is the role of the `Role` selector next to the message input box? :id=role-selector-function

**A**: Each role has the following function:

- **User**<br />Normally select this. Enter a message as a user and immediately send it to the AI agent for a response.
- **User (to add to past messages)**<br />Enter a message as a user, but use it to add to past messages as part of the context. Do not request a direct response from the AI agent.
- **Assistant (to add to past messages)**<br />Add text as a message from the AI assistant. Use it to add to past messages as part of the context.
- **System (to provide additional direction)**<br />Use this to provide additional system prompts.

---

##### Q: When I access localhost:4567 in the browser, it shows "Not Secure". Is this a security concern? :id=localhost-security-warning

**A**: This application is secure because the server only accepts connections from `localhost` (`127.0.0.1`). The "Not Secure" warning shown in your browser is not a concern for this local connection.

---

##### Q: After clicking Stop, the web UI briefly shows "Connecting…" or "Connection lost". Is something wrong? :id=stop-connecting-flicker

**A**: No. When you stop Monadic Chat intentionally, the app's window suppresses reconnection attempts and shows "Stopped" during shutdown. If a tab was left open in an external browser, it may keep trying to reconnect — simply reload it after the next Start.
