# Coding & Notebook Apps

Apps for writing and running code: Python execution in a container, coding assistance, and Jupyter Notebook creation.

## Code Interpreter

![Code Interpreter app icon](../assets/icons/code-interpreter.png ':size=40')

Let the AI write and run Python code in the Python container. Text and images produced by the code are saved to the shared folder and shown in the chat. The AI keeps track of the files it has made, so you can refer to them in later turns. To give the AI your own files (scripts or data), place them in the shared folder and mention their names in your message.

?> **Note:** The Python container includes Japanese fonts (Noto Sans CJK JP), and matplotlib is set up to use them, so Japanese text in plots is displayed correctly.

Code Interpreter availability matches the [availability table](../basic-usage/basic-apps.md#app-availability).


## Coding Assistant

![Coding Assistant app icon](../assets/icons/coding-assistant.png ':size=40')

An assistant for software development. It writes and edits code, and reads and writes files in the shared folder.

**Key Features:**
- Code generation and editing
- Reading and writing files in the shared folder (overwrite or append)
- Listing the files in a folder
- In the OpenAI and xAI (Grok) versions, larger coding tasks are handed to a code generation model of the same provider

?> **Note:** Code Interpreter runs Python code. Coding Assistant writes code and works with files, but does not run code.

Coding Assistant supports the providers indicated in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Jupyter Notebook :id=jupyter-notebook

![Jupyter Notebook app icon](../assets/icons/jupyter-notebook.png ':size=40')

Let the AI create Jupyter notebooks, add cells, and run them as you ask. The AI keeps track of the current notebook, so you can go on editing and running the same notebook over several turns. The code runs in the Python container, and the notebook is saved to the shared folder.

?> You can ask the AI to start or stop JupyterLab, or use **Start JupyterLab** and **Stop JupyterLab** in the **Actions** menu of the console. See [JupyterLab](../docker-integration/jupyterlab.md).
<br /><br /><!-- SCREENSHOT: Monadic Chat Actions menu showing Start JupyterLab and Stop JupyterLab options -->

Jupyter Notebook is available for the providers shown in the [availability table](../basic-usage/basic-apps.md#app-availability).
