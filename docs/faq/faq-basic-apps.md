# FAQ: Basic Applications

##### Q: Is there an easy way to extend the basic apps without programming? :id=extending-basic-apps

**A**: Yes, after selecting an appropriate basic app, you can freely change settings such as system prompts on the Web UI. You can also export the session in the modified state and call the same state when needed.

![](../assets/images/monadic-chat-session.png ':size=400')

---

##### Q: What is the difference between the `Code Interpreter` app and the `Coding Assistant` and `Jupyter Notebook` apps? :id=code-interpreter-vs-coding-assistant

**A**: The `Code Interpreter` app is an application that runs Python scripts using the Python interpreter on the Python container. You can not only ask the AI agent to write Python code but also actually run it and get the results. In addition to Python scripts, you can also read and process CSV files, Microsoft Office files, and audio files (MP3, WAV).

The `Coding Assistant` app provides features to assist in creating various programs (Python, Ruby, JavaScript, etc.). You cannot run code with the AI agent, but you can provide source code and request bug fixes or feature additions.

Though there is a limit to the number of tokens, it is possible to cache the source code and request modifications one after another. The `Coding Assistant` app uses `prompt caching` (Anthropic and OpenAI models) and `predicted outputs` (Open AI models) features to provide an efficient way to request modifications.

The `Jupyter Notebook` app uses JupyterLab to write and execute Jupyter Notebook cells. In addition to asking the AI agent to think about the code to enter in the cell, you can create a notebook (`ipynb` file) in a shared folder and add and execute cells one after another. It can be used as a support tool for creating library tutorials or notebooks for programming education.

---

##### Q: How do I use Monadic Chat in server mode? :id=server-mode-usage

**A**: To run Monadic Chat in server mode:

1. Open the Settings panel by clicking the gear icon in the application
2. Under "System Settings", find "Application Mode"
3. Select "Server Mode" from the dropdown
4. Click "Save" to apply the changes
5. Restart the application

In this mode, Jupyter notebook URLs and other services will use the server's external IP address, and clients can connect to the server through their web browsers.

For more information, see the [Server and Standalone Modes](../docker-integration/basic-architecture.md#server-and-standalone-modes) documentation.

---

##### Q: What happens if I install a new version? :id=version-updates

**A**: When installing a new version, user settings such as API tokens and other configurations are preserved. However, Docker containers might be rebuilt depending on the changes made to the application. If there are changes to Dockerfiles or related files, a full rebuild of all containers will be performed. Otherwise, only the Ruby container gets rebuilt, saving time during updates.

---

##### Q: Why doesn't the app start even though Docker is running? :id=app-startup-issues

**A**: Check the following:

1. Make sure Docker Desktop is running.
2. Ensure that the necessary ports (4567, 5070, 8889) are not already in use by other applications.
3. Look at the console output for any error messages.
4. Try restarting the application or rebuilding the containers from the console.

---

##### Q: Can I use Monadic Chat offline? :id=offline-usage

**A**: While most features require internet access to communicate with language model APIs, you can use Monadic Chat offline with Ollama:

1. Build the Ollama container (Actions → Build Ollama Container)
2. Models are downloaded during the build process based on your `olsetup.sh` script or `OLLAMA_DEFAULT_MODEL` setting
3. Once models are downloaded, you can use the Chat app with Ollama provider offline

Note that other features like web search, image generation, and cloud-based language models still require internet access.

---

##### Q: How can I reset the app to the initial state? :id=app-reset

**A**: To reset the app to its initial state, you can:

1. Click the "Reset" button in the web interface.
2. This will clear the current conversation history.

Note that this doesn't delete any saved files in the shared folder or reset configuration settings.

---

##### Q: Can I have multiple conversations in parallel? :id=multiple-conversations

**A**: Currently, Monadic Chat supports one conversation at a time. However, you can save and export conversations, and switch between different applications to work on different topics.

---

##### Q: What happens if code execution fails repeatedly in Code Interpreter? :id=code-execution-errors

**A**: The Code Interpreter app includes automatic error handling to prevent infinite retry loops. If code execution encounters repeated errors:

1. The app will automatically stop retrying after a reasonable number of attempts
2. An error message will be displayed indicating the issue
3. The AI will provide suggestions for fixing the code or alternative approaches

This prevents the app from getting stuck in infinite loops when encountering persistent errors.