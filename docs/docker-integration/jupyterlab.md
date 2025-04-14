# JupyterLab Integration

Monadic Chat has a feature to launch JupyterLab. JupyterLab is an integrated development environment (IDE) for data science and machine learning. By using JupyterLab, you can perform data analysis and visualization using Python.

## Launching JupyterLab

Click the `Actions/Start JupyterLab` menu in the Monadic Chat console to launch JupyterLab.

- In Standalone Mode: JupyterLab can be accessed at `http://localhost:8889` or `http://127.0.0.1:8889`

![Action menu](../assets/images/jupyter-start-stop.png ':size=190')

When JupyterLab is launched, it starts with `/monadic/data` as its home directory and current working directory. This allows you to access files in the shared folder within JupyterLab.

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
- The JupyterLab interface can be accessed at `http://127.0.0.1:8889`
- The `Jupyter Notebook` app is available in the application menu
- AI agents can create, modify, and execute Jupyter notebooks

### Server Mode Restrictions

When running Monadic Chat in Server Mode, Jupyter features are restricted for security reasons:

- The `Jupyter Notebook` app is automatically hidden from the application menu
- Related apps that depend on Jupyter functionality are also hidden
- Direct access to JupyterLab is still technically possible through the Actions menu
- We recommend using Server Mode only in trusted environments

These restrictions are implemented because Jupyter allows arbitrary code execution, which could be a security risk when exposed to a network.

If you need Jupyter functionality in a multi-user environment, we recommend:
1. Running Monadic Chat in Standalone Mode on individual machines
2. Using Server Mode only for collaborative features that don't require Jupyter

