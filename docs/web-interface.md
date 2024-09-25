# Monadic Chat Web Interface

<img src="./assets/images/monadic-chat-web.png" width="700px"/>

## Chat Settings Screen

<img src="./assets/images/chat-settings.png" width="700px"/>

**Base App** <br />
Select one of the basic apps provided by Monadic Chat. Each app has different default parameter values and unique initial prompts. For the characteristics of each app, see [Base Apps](#base-apps).

**Model** <br />
Models available for the selected app are displayed. If the default mode is set for the app, the default model is selected. You can change the model by selecting a different one from the dropdown list.

!> With many basic apps, the model list is automatically retrieved from the API. If you use a moden other than the default one, there could be an error message shown if the model is not suitable for the app.

**Max Tokens** <br />
When the checkmark is on, the text sent to the API (past interactions and new messages) is limited to the specified number of tokens. For information on how tokens are counted in OpenAI's API, see [What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them).

Specify the number of tokens to limit the text to. This includes the number of tokens in the text sent as a prompt and the number of tokens in the text returned as a response. For information on how tokens are counted in OpenAI's API, see [What are tokens and how to count them](https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them).

**Context Size** <br />
The maximum number of utterances to keep active in the ongoing chat. Only active utterances are sent to OpenAI's chat API as context information. Inactive utterances can still be referenced on the screen and are also saved when exported.

**Parameters**<br />

These elements are sent as parameters to the API. For details on each parameter, see the Chat API [Reference](https://platform.openai.com/docs/api-reference/chat). The values to the parameters not supported by the selected model are just ignored.

- Temperature
- Top P
- Presence Penalty
- Frequency Penalty

**Show Initial Prompt**<br />
Turn on to display or edit the text sent to the API as the initial prompt (also called the system prompt). The initial prompt can specify the character settings of the conversation and the format of the response. Default text is set according to the purpose of each app, but it can be freely changed.

**Show Initial Prompt for AI-User**<br />
Displays the initial prompt given to the AI user when the AI User feature is enabled. When the AI user is enabled, the first message must be created by the (non-AI) user. The AI user will then continue the conversation based on the initial prompt. The initial prompt for the AI user can be freely changed.

**Enable AI-User**<br />
Specify whether to enable the AI User feature. When enabled, you cannot turn on the `Start from assistant` option.

**Chat Interaction Controls**<br />
Options to set Monadic Chat in a form suitable for conversation with voice input. If you are having a conversation with voice input, it is recommended to turn on all the following options (`Start from assistant`, `Auto speech`, `Easy submit`). You can turn all options on or off at once by clicking `check all` or `uncheck all`.

**Start from assistant**<br />

When on, the assistant makes the first utterance when starting a conversation.

**Auto speech**<br />

When on, the response from the assistant is automatically read aloud with synthesized speech when it is returned. The speech voice, speed, and language can be set in the Speech Settings panel.

**Easy submit**<br />

When on, the message in the text area is automatically sent by pressing the Enter key on the keyboard without clicking the `Send` button. If you are in the middle of voice input, pressing the Enter key or clicking the `Stop` button will automatically send the message.

**Start Session** <br />
Click this button to start a chat with the options and parameters specified in the settings.

## Info Panel

<img src="./assets/images/monadic-chat-info.png" width="400px"/>

**Monadic Chat Info**<br />
Links to related websites and the version of Monadic Chat are shown. Clicking `API Usage` will take you to the OpenAI page. Note that the API Usage shown is the overall API usage and may not be limited to Monadic Chat. The style in which Monadic Chat was installed is displayed in parentheses after the version number, either Docker or Local.

**Current Base App**<br />
The name and description of the currently selected base app are displayed. When Monadic Chat is launched, information about the default app, `Chat`, is displayed.

## Status Panel

<img src="./assets/images/monadic-chat-status.png" width="400px"/>

**Monadic Chat Status**<br />

The status of the conversation is displayed. The status is updated in real-time as the conversation progresses. 

**Model Selected**<br />

The model selected for the current conversation is displayed.

**Monadic Chat Stats**<br />

The numbers of messages and tokens exchanged in the current conversation are displayed.

## Session Panel

<img src="./assets/images/monadic-chat-session.png" width="400px"/>

**Reset**<br />
Clicking the `Reset` button will discard the current conversation and return to the initial state. The app selection will also revert to the default `Chat`.

**Settings**<br />
Clicking the `Settings` button will return to the GPT Settings panel without discarding the current conversation. To return to the current conversation, click `Continue Session`.

**Import**<br />
Clicking the `Import` button will discard the current conversation and load conversation data saved in an external file (JSON). The settings saved in the external file will also be applied.

**Export**<br />
Clicking the `Export` button will save the current settings and conversation data to an external file (JSON).

## Speech Settings Panel

<img src="./assets/images/monadic-chat-tts.png" width="400px"/>

**NOTE**: To use the speech feature, you need to use the Google Chrome or Microsoft Edge browser.

**Text-to-Speech (TTS) Voice**<br />
You can specify the voice used for speech synthesis.

**TTS Speed**<br />
You can specify the speech speed for speech synthesis between 0.5 and 1.5 (default: 0.0).

**Automatic-Speech-Recognition (ASR) Language**<br />
Whisper API is used for speech recognition, and if `Automatic` is selected, it automatically recognizes voice input in different languages. If you want to specify a particular language, select the language in the selector.
Reference: [Whisper API FAQ](https://help.openai.com/en/articles/7031512-whisper-api-faq)

## PDF Database Display Panel

<img src="./assets/images/monadic-chat-pdf-db.png" width="400px"/>

?> This panel is displayed only when an app with PDF reading functionality is selected.

**Uploaded PDF**<br />
Here, a list of PDFs uploaded by clicking the `Import PDF` button is displayed. You can assign a unique display name to the file when uploading a PDF. If not specified, the original file name is used. Multiple PDF files can be uploaded. Clicking the trash can icon to the right of the PDF file display name will discard the contents of that PDF file.

!> The text from PDF files are coverted to text embeddings and stored in the PGVector database. The database will be cleared when the Docker container is rebuilt or when Monadic Chat is updated. Export the database using the 'Export Document DB' feature to save and restore the data.
