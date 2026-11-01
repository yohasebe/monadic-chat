# FAQ: Basic Applications

##### Q: Is there an easy way to extend the basic apps without programming? :id=extending-basic-apps

**A**: Yes, after selecting an appropriate basic app, you can freely change settings such as system prompts on the Web UI. You can also export the session in the modified state and call the same state when needed.

---

##### Q: What is the difference between the `Code Interpreter` app and the `Coding Assistant` and `Jupyter Notebook` apps? :id=code-interpreter-vs-coding-assistant

**A**: The `Code Interpreter` app is an application that runs Python scripts using the Python interpreter on the Python container. You can not only ask the AI agent to write Python code but also actually run it and get the results. It can also read text files such as CSV, PDF and Microsoft Office files, and process other files, such as audio, with Python code.

The `Coding Assistant` app provides features to assist in creating various programs (Python, Ruby, JavaScript, etc.). It does not run code, but it can read, write and list files in the shared folder, so you can give it source code and ask for bug fixes or new features. The Claude version uses prompt caching for repeated changes.

The `Jupyter Notebook` app uses JupyterLab to write and execute Jupyter Notebook cells. In addition to asking the AI agent to think about the code to enter in the cell, you can create a notebook (`ipynb` file) in a shared folder and add and execute cells one after another. It can be used as a support tool for creating library tutorials or notebooks for programming education.

---

##### Q: What happens if I install a new version? :id=version-updates

**A**: When installing a new version, user settings such as API tokens and other configurations are preserved. On the first Start after an update, the Ruby container is rebuilt, and the Python, Selenium and embeddings containers are rebuilt or downloaded again only when their definitions changed.

---

##### Q: Why doesn't the app start even though Docker is running? :id=app-startup-issues

**A**: Check the following:

1. Make sure Docker Desktop is running.
2. Ensure that the necessary ports (4567, 3100, 8889, 4444, 5900, 7900) are not already in use by other applications.
3. Look at the console output for any error messages.
4. Try restarting the application, or rebuild the containers from the **Actions** menu (for example **Build All**).

---

##### Q: Can I use Monadic Chat offline? :id=offline-usage

**A**: While most features require internet access to communicate with language model APIs, you can use Monadic Chat offline with Ollama:

1. Install Ollama on your system ([ollama.com](https://ollama.com/download))
2. Pull the models you need (`ollama pull <model-name>`)
3. Once models are downloaded, you can use the Chat app with Ollama provider offline

Note that other features like web search, image generation, and cloud-based language models still require internet access.

The first start needs a connection to download the container images and build the Ruby container. After that, Monadic Chat also starts without a connection and shows which features are unavailable until you are back online.

---

##### Q: How can I reset the app to the initial state? :id=app-reset

**A**: To reset the app to its initial state, you can:

1. Click the **Reset** button in the web interface.
2. This clears the current conversation and returns the parameters to their defaults; the selected app stays. If the conversation can be saved, the confirmation dialog also offers to save it to the Knowledge Base first.

Reset does not delete files in the shared folder or change the settings.

---

##### Q: Can I have multiple conversations in parallel? :id=multiple-conversations

**A**: Yes. Each browser tab is an independent conversation session, so you can open multiple tabs and run different apps or topics in parallel. You can also save and export conversations to revisit them later.

---

##### Q: What happens if code execution fails repeatedly in Code Interpreter? :id=code-execution-errors

**A**: The Code Interpreter app includes automatic error handling to prevent infinite retry loops. If code execution encounters repeated errors:

1. After the same kind of error three times, the retries stop
2. A message describes the problem
3. The AI suggests how to fix the code or another approach

This prevents the app from getting stuck in infinite loops when encountering persistent errors.