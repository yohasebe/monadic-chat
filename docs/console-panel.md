# Monadic Chat Console Panel

## Console Button Items

![Monadic Chat Console](./assets/images/monadic-chat-console.png ':size=700')

**Start** Launch Monadic Chat. The initial startup may take some time due to environment setup on Docker.

**Stop** <br />
Stop Monadic Chat.

**Restart** <br />
Restart Monadic Chat.

**Open Browser** <br />
Open the default browser to access Monadic Chat at `http://localhost:4567`.

**Shared Folder** <br />
Open the folder shared between the host and Docker containers. It can be used for importing and exporting files. It is also used when installing additional apps.

**Quit** <br />
Exit the Monadic Chat Console.

## Console Menu Items

![Console Menu](./assets/images/console-menu.png ':size=300')

![Action Menu](./assets/images/action-menu.png ':size=150')

**Rebuild All** <br />
Rebuild all Docker images and containers for Monadic Chat.

**Rebuild Ruby Container** <br />
Rebuild the Docker image and container (`monadic-chat-ruby-container`) that powers Monadic Chat.

**Rebuild Python Container** <br />
Rebuild the Docker image and container (`monadic-chat-python-container`) used by the AI agents.

**Rebuild User Containers** <br />
Rebuild the Docker images and containers defined by the user.

**Uninstall Images and Containers** <br />
Remove the Docker images and containers for Monadic Chat.

**Start JupyterLab** <br />
Launch JupyterLab. It can be accessed at `http://localhost:8889`.

**Stop JupyterLab** <br />
Stop JupyterLab.

**Export Document DB** <br />
Export PDF document data stored in Monadic Chat's PGVector database. The exported file will be saved as `monadic.gz` in the shared folder.

**Import Document DB** <br />
Import PDF document data exported by Monadic Chat's export feature into the PGVector database. When importing, place a file named `monadic.gz` in the shared folder.

## API Token Settings Panel

![Settings Panel](./assets/images/settings-panel.png ':size=600')

All settings here are saved in the `~/monadic/data/.env` file.

**OPENAI_API_KEY** <br />
(Required) Enter your OpenAI API key. This key is used to access the Chat API, DALL-E image generation API, Whisper speech recognition API, and speech synthesis API. It can be obtained from the [OpenAI API page](https://platform.openai.com/docs/guides/authentication).

**Syntax Highlighting Theme** <br />
Select the theme for code syntax highlighting. The default is `monokai`.

**VISION_MODEL** <br />
Select the model used for image and video recognition. Currently, `gpt-4o` and `gpt-4o-mini` are available. The default is `gpt-4o-mini`.

**AI_USER_MODEL** <br />
Select the model used for the AI User feature, which creates messages on behalf of the user. Currently, `gpt-4o` and `gpt-4o-mini` are available. The default is `gpt-4o-mini`.

**ANTHROPIC_API_KEY** <br />
Enter your Anthropic API key. This key is required to use the Anthropic Claude (Chat) and Anthropic Claude (Code Interpreter) apps. It can be obtained from [https://console.anthropic.com].

**COHERE_API_KEY** <br />
Enter your Cohere API key. This key is required to use the Cohere Command R (Chat) and Cohere Command R (Code Interpreter) apps. It can be obtained from [https://dashboard.cohere.com].

**GEMINI_API_KEY** <br />
Enter your Google Gemini API key. This key is required to use the Google Gemini (Chat) app. It can be obtained from [https://ai.google.dev/].

**MISTRAL_API_KEY** <br />
Enter your Mistral API key. This key is required to use the Mistral AI (Chat) app. It can be obtained from [https://console.mistral.ai/].

