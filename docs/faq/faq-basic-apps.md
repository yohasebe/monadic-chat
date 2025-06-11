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
2. Ensure that the necessary ports (4567, 5070, 8889) are not already in use by other applications.
3. Look at the console output for any error messages.
4. Try restarting the application or rebuilding the containers from the console.

**Q**: Can I use Monadic Chat offline?

**A**: While most features require internet access to communicate with language model APIs, you can use Monadic Chat offline with Ollama:

1. Build the Ollama container (Actions → Build Ollama Container)
2. Install local models using the `olsetup.sh` script
3. Use the Chat app with Ollama provider

Note that other features like web search, image generation, and cloud-based language models still require internet access.

**Q**: How can I reset the app to the initial state?

**A**: To reset the app to its initial state, you can:

1. Click the "Reset" button in the web interface.
2. This will clear the current conversation history.

Note that this doesn't delete any saved files in the shared folder or reset configuration settings.

**Q**: Can I have multiple conversations in parallel?

**A**: Currently, Monadic Chat supports one conversation at a time. However, you can save and export conversations, and switch between different applications to work on different topics.

**Q**: What happens if code execution fails repeatedly in Code Interpreter?

**A**: The Code Interpreter app includes automatic error handling to prevent infinite retry loops. If code execution encounters repeated errors:

1. The app will automatically stop retrying after a reasonable number of attempts
2. An error message will be displayed indicating the issue
3. The AI will provide suggestions for fixing the code or alternative approaches

This prevents the app from getting stuck in infinite loops when encountering persistent errors.

**Q**: How can I display Japanese text in matplotlib plots?

**A**: The Python container includes built-in Japanese font support. When using matplotlib:

- The Noto Sans CJK JP font is automatically configured
- Japanese text will render correctly in plots without additional setup
- The configuration is handled through the `/monadic/matplotlibrc` file
- You can customize font settings by creating your own `matplotlibrc` file in the shared folder

Example code that will work correctly with Japanese text:
```python
import matplotlib.pyplot as plt
plt.plot([1, 2, 3], [1, 4, 9])
plt.title('Sample Plot')
plt.xlabel('X-axis')
plt.ylabel('Y-axis')
plt.show()
# Japanese characters like あいうえお, 漢字, etc. will display correctly
```

**Q**: Why does Jupyter Notebook fail to start in the Jupyter Notebook app?

**A**: If Jupyter Notebook fails to start, it might be due to command execution issues. Check the following:

1. Ensure the Python container is running (check container status in the console)
2. Try manually starting JupyterLab by accessing the console and running "Start JupyterLab"
3. Check if port 8889 is available and not blocked by another application
4. If using local development mode, ensure the Ruby container paths are correctly configured

The app should automatically start JupyterLab when you use the `run_jupyter` function.

**Q**: Why does text-to-speech (TTS) fail with "command not found" errors?

**A**: This can occur when running in local development mode. The issue typically happens because:

1. Script paths are not properly configured when Ruby container is stopped
2. The TTS scripts are located in subdirectories that need to be in PATH

To resolve:
- Ensure all containers are running normally, or
- If developing locally, the system will automatically configure the correct paths for scripts in `cli_tools`, `utilities`, and other subdirectories