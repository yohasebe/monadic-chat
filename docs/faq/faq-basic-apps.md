# FAQ: Basic Applications

**Q**: Is there an easy way to extend the basic apps without programming?

**A**: Yes, after selecting an appropriate basic app, you can freely change settings such as system prompts on the Web UI. You can also export the session in the modified state and call the same state when needed.

![](../assets/images/monadic-chat-session.png ':size=400')

**Q**: What is the difference between the `Code Interpreter` app and the `Coding Assistant` and `Jupyter Notebook` apps?

**A**: The `Code Interpreter` app is an application that runs Python scripts using the Python interpreter on the Python container. You can not only ask the AI agent to write Python code but also actually run it and get the results. In addition to Python scripts, you can also read and process CSV files, Microsoft Office files, and audio files (MP3, WAV).

The `Coding Assistant` app provides features to assist in creating various programs (Python, Ruby, JavaScript, etc.). You cannot run code with the AI agent, but you can provide source code and request bug fixes or feature additions.

Though there is a limit to the number of tokens, it ispossible to cache the source code and request modifications one after another. The `Coding Assistant` app uses `prompt caching` (Anthropic and OpenAI models) and `predicted outputs` (Open AI models) features to provide an efficient way to request modifications.

The `Jupyter Notebook` app uses JupyterLab to write and execute Jupyter Notebook cells. In addition to asking the AI agent to think about the code to enter in the cell, you can create a notebook (`ipynb` file) in a shared folder and add and execute cells one after another. It can be used as a support tool for creating library tutorials or notebooks for programming education.

**Q**: How do I use Monadic Chat in server mode?

**A**: To run Monadic Chat in server mode:

1. Open the Settings panel by clicking the gear icon in the application
2. Select "Server Mode" from the options
3. Click "Save" to apply the changes
4. Restart the application

In this mode, Jupyter notebook URLs and other services will use the server's external IP address, and clients can connect to the server through their web browsers.

For more information, see the [Server and Standalone Modes](../docker-integration/basic-architecture.md#server-and-standalone-modes) documentation.

**Q**: What happens if I install a new version?

**A**: When installing a new version, user settings such as API tokens and other configurations are preserved. However, Docker containers might be rebuilt depending on the changes made to the application. If there are changes to Dockerfiles or related files, a full rebuild of all containers will be performed. Otherwise, only the Ruby container gets rebuilt, saving time during updates.

**Q**: Why doesn't the app start even though Docker is running?

**A**: Check the following:

1. Make sure Docker Desktop is running.
2. Ensure that the necessary ports (3330, 3000, 8889) are not already in use by other applications.
3. Look at the console output for any error messages.
4. Try restarting the application or rebuilding the containers from the console.

**Q**: Can I use Monadic Chat offline?

**A**: No, Monadic Chat requires internet access to communicate with the language model APIs. The application itself runs locally, but the AI features depend on online services.

**Q**: How can I reset the app to the initial state?

**A**: To reset the app to its initial state, you can:

1. Click the "Reset" button in the web interface.
2. This will clear the current conversation history.

Note that this doesn't delete any saved files in the shared folder or reset configuration settings.

**Q**: Can I have multiple conversations in parallel?

**A**: Currently, Monadic Chat supports one conversation at a time. However, you can save and export conversations, and switch between different applications to work on different topics.