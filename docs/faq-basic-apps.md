# FAQ: Basic Applications

**Q**: Is there an easy way to extend the basic apps without programming?

**A**: Yes, after selecting an appropriate basic app, you can freely change settings such as system prompts on the Web UI. You can also export the session in the modified state and call the same state when needed.

![](./assets/images/monadic-chat-session.png ':size=400')

**Q**: What is the difference between the `Code Interpreter` app and the `Coding Assistant` and `Jupyter Notebook` apps?

**A**: The `Code Interpreter` app is an application that runs Python scripts using the Python interpreter on the Python container. You can not only ask the AI agent to write Python code but also actually run it and get the results. In addition to Python scripts, you can also read and process CSV files, Microsoft Office files, and audio files (MP3, WAV).

The `Coding Assistant` app provides features to assist in creating various programs (Python, Ruby, JavaScript, etc.). You cannot run code with the AI agent, but you can provide source code and request bug fixes or feature additions.

Though there is a limit to the number of tokens, it ispossible to cache the source code and request modifications one after another. The `Coding Assistant` app uses `prompt caching` (Anthropic and OpenAI models) and `predicted outputs` (Open AI models) features to provide an efficient way to request modifications.

The `Jupyter Notebook` app uses JupyterLab to write and execute Jupyter Notebook cells. In addition to asking the AI agent to think about the code to enter in the cell, you can create a notebook (`ipynb` file) in a shared folder and add and execute cells one after another. It can be used as a support tool for creating library tutorials or notebooks for programming education.

