# JupyterLab Integration

Monadic Chat has a feature to launch JupyterLab. JupyterLab is an integrated development environment (IDE) for data science and machine learning. By using JupyterLab, you can perform data analysis and visualization using Python.

## Launching JupyterLab

Click the `Actions/Start JupyterLab` menu in the Monadic Chat console to launch JupyterLab. JupyterLab can be accessed at `http://localhost:8889`.

![Action menu](/assets/images/action-menu.png ':size=150')

When JupyterLab is launched, it starts with `/monadic/data` as its home directory and current working directory. This allows you to access files in the shared folder within JupyterLab.

![JupyterLab Terminal](/assets/images/jupyterlab-terminal.png ':size=600')

## Stopping JupyterLab

To stop JupyterLab, close the JupyterLab tab or click the `Actions/Stop JupyterLab` menu in the Monadic Chat console.

## Using JupyterLab App

In the basic Jupyter Notebook app of Monadic Chat, you can do the following by interacting with the AI agent in the chat:

- Start and stop JupyterLab
- Create new notebooks in the shared folder
- Load notebooks from the shared folder
- Add new cells to notebooks
