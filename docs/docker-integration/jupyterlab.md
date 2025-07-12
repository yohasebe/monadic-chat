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
- **Python Packages**: Additional packages can be installed using `pip install` in notebook cells
- **Terminal Access**: Use the Terminal in JupyterLab to access the Python container directly


## Related Apps

- **Code Interpreter**: Executes Python code directly in chat without needing to open JupyterLab
- **Jupyter Notebook**: AI agent that can create and manage Jupyter notebooks through chat
- Both apps use the same Python environment as JupyterLab

