# JupyterLab Integration

Monadic Chat has a feature to launch JupyterLab. JupyterLab is an integrated development environment (IDE) for data science and machine learning. By using JupyterLab, you can perform data analysis and visualization using Python.

## Launching JupyterLab

Click the `Actions/Start JupyterLab` menu in the Monadic Chat console to launch JupyterLab.

- JupyterLab can be accessed at [http://localhost:8889](http://localhost:8889) or [http://127.0.0.1:8889](http://127.0.0.1:8889)
- No password or token is required (configured for local use only)


![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

When JupyterLab is launched, it starts with `/monadic/data` as its home directory and current working directory. This allows you to access files in the shared folder within JupyterLab.

<!-- > 📸 **Screenshot needed**: JupyterLab interface showing file browser with shared folder -->

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')

## Stopping JupyterLab

To stop JupyterLab, close the JupyterLab tab or click the `Actions/Stop JupyterLab` menu in the Monadic Chat console.

## Using JupyterLab App

In the basic Jupyter Notebook app of Monadic Chat, you can do the following by interacting with the AI agent in the chat:

- Start and stop JupyterLab
- Create new notebooks in the shared folder
- Load notebooks from the shared folder
- Add new cells to notebooks

### Provider-Specific Limitations

#### xAI/Grok
When using Jupyter Notebook with xAI/Grok models:
- **Sequential operations required**: Cannot execute multiple tools in a single request
- **Step-by-step approach**: Break down complex requests (e.g., "Create notebook" then "Add graph")
- **Initial guidance**: The AI will explain the sequential approach in its greeting message


## Jupyter Access in Different Modes

### Standalone Mode

In Standalone Mode, all Jupyter features are fully available:
- The JupyterLab interface can be accessed at [http://127.0.0.1:8889](http://127.0.0.1:8889)
- The `Jupyter Notebook` app is available in the application menu
- AI agents can create, modify, and execute Jupyter notebooks

### Server Mode Restrictions

When running Monadic Chat in Server Mode, Jupyter features are disabled by default for security reasons:

- **Jupyter apps are hidden** from the application menu in Server Mode
- To enable Jupyter in Server Mode, set the configuration variable: `ALLOW_JUPYTER_IN_SERVER_MODE=true` in `~/monadic/config/env`
- Server Mode allows network access from multiple devices
- JupyterLab is tied to the shared folder, which poses security risks if accessed by untrusted users
- We strongly recommend using Server Mode only in trusted environments
- **WARNING**: Enabling Jupyter in Server Mode allows arbitrary code execution with full access to the shared folder

To enable Jupyter apps in Server Mode, add the following to your `~/monadic/config/env` file:
```
ALLOW_JUPYTER_IN_SERVER_MODE=true
```

These restrictions exist because Jupyter allows arbitrary code execution, which can be dangerous in multi-user environments.

## Tips for Using JupyterLab

- **Working Directory**: JupyterLab starts with `/monadic/data` as the working directory
- **Persistent Storage**: All files saved in `/monadic/data` persist across container restarts
- **Python Packages**: Additional packages can be installed in notebook cells:
  - `!uv pip install --no-cache package_name` (recommended)
  - `!pip install package_name`
- **Terminal Access**: Use the Terminal in JupyterLab to access the Python container directly


## Japanese Text Support

Monadic Chat's Jupyter Notebook applications now include automatic Japanese font configuration for matplotlib plots.

### Automatic Font Setup

When you create or run a Jupyter notebook that contains:
- Japanese text (Hiragana, Katakana, or Kanji characters)
- matplotlib imports or usage

The system automatically inserts a font configuration cell that:
1. Configures matplotlib to use Japanese fonts (Noto Sans CJK JP or IPAGothic)
2. Suppresses font-related warnings
3. Ensures proper display of Japanese characters in plots

### How It Works

The font setup code is automatically inserted:
- After the first matplotlib import statement (if present)
- Or at the beginning of the notebook (if no imports found)
- Only when Japanese text or matplotlib usage is detected
- Only if not already present (tagged with "font-setup" metadata)

### Supported Fonts

The system checks for the following fonts in order:
1. Noto Sans CJK JP (preferred)
2. IPA Gothic
3. System-configured Japanese fonts

### Example

When you create a notebook with Japanese text:

```python
import matplotlib.pyplot as plt
import numpy as np

# Plot with Japanese labels
plt.plot([1, 2, 3], [1, 4, 2])
plt.title('日本語のタイトル')
plt.xlabel('横軸')
plt.ylabel('縦軸')
plt.show()
```

The system automatically adds the font configuration before your code runs, ensuring Japanese text displays correctly.

### Technical Details

#### Font Paths
The system checks these font locations:
- `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc`
- `/usr/share/fonts/opentype/ipafont/ipag.ttf`
- `/usr/share/fonts/truetype/ipafont/ipag.ttf`

#### Configuration
- Font family: sans-serif
- Unicode minus: disabled (prevents minus sign display issues)
- Warnings: suppressed for missing glyphs

### Troubleshooting

If Japanese text still doesn't display:
1. Restart the Jupyter kernel
2. Re-run all cells
3. Check that the font setup cell executed successfully
4. Verify fonts are installed in the Python container

### Notes

- This feature is available for all Jupyter Notebook apps (OpenAI, Claude, Gemini, Grok)
- The font setup is persistent within each notebook session
- No manual configuration required - it's automatic!

## Related Apps

- **Code Interpreter**: Executes Python code directly in chat without needing to open JupyterLab
- **Jupyter Notebook**: AI agent that can create and manage Jupyter notebooks through chat
- Both apps use the same Python environment as JupyterLab

