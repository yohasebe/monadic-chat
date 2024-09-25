# Standard Docker Containers

This section explains how to access Docker containers. By default, the following containers are built:

**Ruby Container** (`monadic-chat-ruby-container`)

A container used to run Monadic Chat applications. It is also used to provide the web interface.

**Python Container** (`monadic-chat-python-container`)

A container used to run Python scripts that extend the functionality of Monadic Chat. JupyterLab is also run on this container.

**Selenium Container** (`monadic-chat-selenium-container`)

A container used to operate a virtual web browser using Selenium for web scraping.

**pgvector Container** (`monadic-chat-pgvector-container`)

A container used to save text embedding vector data on Postgresql for using pgvector.

You can install new software on a Docker container or edit files to extend the functionality of Monadic Chat.

# Accessing Docker Containers

There are two ways to access a Docker container.

## Docker Command

To access a Docker container, use the `docker exec` command. For example, to access the `monadic-chat-python-container`, execute the following command in the terminal:

```shell
docker exec -it monadic-chat-python-container bash
```

When you click Start on the Monadic Chat console, all containers will start. Once the startup is complete, a command to access the container will be displayed, which you can copy and paste into the terminal to execute.

![Start JupyterLab](../assets/images/docker-commands.png ':size=600')

## JupyterLab

By using the `Actions/Start JupyterLab` menu in the Monadic Chat console, you can start JupyterLab, which will launch with `/monadic/data` as the current directory on the Python container. By clicking `Terminal` on the JupyterLab Launcher screen, you can access the Python container.

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')
