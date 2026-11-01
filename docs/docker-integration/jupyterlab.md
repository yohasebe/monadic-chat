# JupyterLab Integration

Monadic Chat can start JupyterLab, an environment for data analysis and visualization with Python, in the Python container.

## Launching JupyterLab

Choose **Actions → Start JupyterLab** in the Monadic Chat console. The menu item is available while Monadic Chat is running.

- JupyterLab opens at [http://localhost:8889](http://localhost:8889) (or [http://127.0.0.1:8889](http://127.0.0.1:8889))
- No password or token is required; JupyterLab is reachable only from your computer

<!-- SCREENSHOT: Monadic Chat Actions menu showing Start JupyterLab and Stop JupyterLab options -->

JupyterLab starts in the shared folder (`/monadic/data`), so the files you place in `~/monadic/data` are available there.

<!-- SCREENSHOT: JupyterLab terminal window showing command prompt at /monadic/data directory -->

## Stopping JupyterLab

Choose **Actions → Stop JupyterLab**. JupyterLab keeps running when you close its browser tab, and it stops when Monadic Chat stops.

## Using the Jupyter Notebook App

In the Jupyter Notebook app, you ask the AI agent in the chat to work with notebooks. The agent can:

- Start and stop JupyterLab
- Create notebooks in the shared folder and list the existing ones
- Add, edit, move, and delete cells, and run them
- Read the outputs of cells and fix cells that raise errors
- Restart or interrupt the kernel

For a task with several steps, the app first proposes a numbered plan and waits for your approval before carrying it out.

The Jupyter Notebook app is available for OpenAI, Anthropic, Gemini, and xAI.

## Tips for Using JupyterLab

- **Saved files**: Files saved in `/monadic/data` are kept in `~/monadic/data` on your computer
- **Python packages**: `!uv pip install --no-cache package_name` in a notebook cell installs a package that stays until the container is recreated, for example by a rebuild or an update. To keep packages across rebuilds, see [Python Container](python-container.md)
- **Terminal**: The Terminal in JupyterLab opens a shell in the Python container

## Japanese Text in Plots

When the Jupyter Notebook app adds cells that contain Japanese text or use matplotlib, it adds a font setup cell along with them, so Japanese text in matplotlib plots is displayed with the Noto Sans CJK JP font installed in the Python container.

For example, the labels in this code are displayed in Japanese:

```python
import matplotlib.pyplot as plt

plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

If Japanese text is still not displayed, restart the kernel and run all cells again, starting with the font setup cell.

## Related Apps

- **Code Interpreter**: runs Python code directly in the chat, without opening JupyterLab
- **Jupyter Notebook**: creates and edits Jupyter notebooks through the chat
- Both apps use the same Python environment as JupyterLab
