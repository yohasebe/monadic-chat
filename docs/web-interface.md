# Monadic Chat Web Interface

![](./assets/images/monadic-chat-web.png ':size=700')

## Chat Settings Screen

![](./assets/images/chat-settings.png ':size=700')

**Base App** <br />
Select one of the basic apps provided by Monadic Chat. Each app has different default parameter values and unique initial prompts. For the characteristics of each app, see [Base Apps](./basic-apps.md).

**Model** <br />
Models available for the selected app are displayed. If a default model is set for the app, the default model is pre-selected. You can change the model by selecting a different one from the dropdown list.  With many basic apps, the model list is automatically retrieved from the API, and multiple models are selectable. Please note that using a model other than the default one might result in errors if the model isn't suitable for the app.

**Reasoning Effort** <br />
For models capable of advanced reasoning (such as `o1` and `o3-mini` from OpenAI), you can adjust the number of tokens used for inference. Selecting `low` minimizes the number of tokens used in the inference process, while selecting `high` maximizes the number of tokens used. The default is `medium`, which is in between.

**Max Tokens** <br />
When the checkmark is on, the text sent to the API (past interactions and new messages) is limited to the specified number of tokens. The method for counting tokens varies depending on the model. For OpenAI models, see [What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them).

Specify the maximum number of tokens to be sent to the API. This includes the number of tokens in the text sent as a prompt and the number of tokens in the text returned as a response. For information on how tokens are counted in OpenAI's API, see [What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them).

**Max Context Size** <br />
The maximum number of utterances to keep active in the ongoing chat. Only active utterances are sent to the API as context information. Inactive utterances can still be referenced on the screen and are also saved when exported.

**Parameters**<br />

These elements are sent as parameters to the API. For details on each parameter, see the Chat API [Reference](https://platform.openai.com/docs/api-reference/chat). Note that parameters not supported by the selected model are ignored.

- Temperature
- Top P
- Presence Penalty
- Frequency Penalty

**Show Initial Prompt**<br />
Turn on to display or edit the text sent to the API as the initial prompt (also called the system prompt). The initial prompt can specify the character settings of the conversation and the format of the response. Default text is set according to the purpose of each app, but it can be freely changed.

**Show Initial Prompt for AI-User**<br />
Displays the initial prompt given to the AI user when the AI User feature is enabled. When the AI user is enabled, the first message must be created by the (non-AI) user.  Afterward, the AI will create messages on your behalf, based on the AI assistant's messages. You can edit or append to the messages entered in the text box by the AI user. The initial prompt for the AI user can be freely changed.

**Prompt Caching**<br />
Specify whether to cache the system prompt sent to the API. Enabling caching allows the same system prompt to be reused on the API side, saving API usage and improving response time. At present, this feature is only available for Anthropic's Claude model and is limited to system prompts, images, and PDFs.

**Enable AI-User**<br />
Specify whether to enable the AI User feature. This feature cannot be used together with the `Start from assistant` feature.

**Start from assistant**<br />
When on, the assistant makes the first utterance when starting a conversation.

**Chat Interaction Controls**<br />
Options to configure Monadic Chat for conversations using voice input. For conversations with voice input, it is recommended to turn on all the following options (`Start from assistant`, `Auto speech`, `Easy submit`). You can turn all options on or off at once by clicking `check all` or `uncheck all`.

**Auto speech**<br />
When on, the assistant's response is automatically read aloud using synthesized speech when it is returned. You can select the voice, speaking speed, and language (automatic or specified) for synthesized speech on the web interface.

**Easy submit**<br />
When on, pressing the Enter key on the keyboard automatically sends the message in the text area without clicking the `Send` button. If you are using voice input, pressing the Enter key or clicking the `Stop` button will automatically send the message.

**Start Session** <br />
Click this button to start a chat based on the options and parameters specified in the Chat Settings.

## Info Panel

![](./assets/images/monadic-chat-info.png ':size=400')

**Monadic Chat Info**<br />
Links to related websites and the version of Monadic Chat are shown. Clicking `API Usage` will take you to the OpenAI page. Note that the API Usage shown is the overall API usage and may not be limited to Monadic Chat.  The style in which Monadic Chat was installed (Docker or Local) is displayed in parentheses after the version number.

**Current Base App**<br />
The name and description of the currently selected base app are displayed. When Monadic Chat is launched, information about the default app, `Chat`, is displayed.

## Status Panel

![](./assets/images/monadic-chat-status.png ':size=400')

**Monadic Chat Status**<br />
Shows the current status of the conversation. The status is updated in real-time as the conversation progresses.

**Model Selected**<br />
Displays the model currently selected for the conversation.

**Model Chat Stats**<br />
Shows details such as the number of messages and tokens exchanged in the current session.


## Session Panel

![](./assets/images/monadic-chat-session.png ':size=400')

**Reset**<br />
Clicking the `Reset` button discards the current conversation and returns to the initial state. The app selection will also revert to the default `Chat`.

**Settings**<br />
Clicking the `Settings` button returns to the Chat Settings panel without discarding the current conversation. To return to the current conversation, click `Continue Session`.

**Import**<br />
Clicking the `Import` button discards the current conversation and loads conversation data saved in an external file (JSON). The settings saved in the external file will also be applied.

**Export**<br />
Clicking the `Export` button saves the current settings and conversation data to an external file (JSON).

## Speech Settings Panel

![](./assets/images/monadic-chat-tts.png ':size=400')

!> To use the speech feature, you need to use the Google Chrome or Microsoft Edge browser.

**Text-to-Speech (TTS) Voice**<br />
You can specify the voice used for speech synthesis.

**TTS Speed**<br />
You can specify the speech speed for speech synthesis between 0.5 and 1.5 (default: 1.0).

**Automatic Speech Recognition (ASR) Language**<br />
Whisper API is used for speech recognition, and if `Automatic` is selected, it automatically recognizes voice input in different languages. If you want to specify a particular language, select the language from the selector.
Reference: [Whisper API FAQ](https://help.openai.com/en/articles/7031512-whisper-api-faq)


## PDF Database Display Panel

![](./assets/images/monadic-chat-pdf-db.png ':size=400')

> This panel is displayed only when an app with PDF reading functionality is selected.

**Uploaded PDF**<br />
This displays a list of PDFs uploaded by clicking the `Import PDF` button. You can give a unique display name to the file when uploading a PDF. If not specified, the original file name is used. Multiple PDF files can be uploaded. Clicking the trash can icon to the right of the PDF file display name will discard the contents of that PDF file.

!> The text from PDF files is converted to text embeddings and stored in the PGVector database. The database will be cleared when the Docker container is rebuilt or when Monadic Chat is updated. Export the database using the `Export Document DB` feature to save and restore the data.

