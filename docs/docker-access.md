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
