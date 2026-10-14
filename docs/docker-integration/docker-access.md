# Accessing Docker Containers

You can work inside the containers with the `docker exec` command or through the JupyterLab terminal.

## Docker Command

After Start, the console lists the running containers together with the `docker exec` command for each one.

### Available Containers

This list shows the standard containers; see [Basic Architecture](basic-architecture.md#standard-containers) for what each one does.

- **Ruby Container** (`monadic-chat-ruby-container`): the Monadic Chat server
  ```shell
  docker exec -it monadic-chat-ruby-container bash
  ```

- **Python Container** (`monadic-chat-python-container`): code execution and data analysis
  ```shell
  docker exec -it monadic-chat-python-container bash
  ```

- **Qdrant Container** (`monadic-chat-qdrant-container`): the vector database
  ```shell
  docker exec -it monadic-chat-qdrant-container bash
  ```

- **Embeddings Container** (`monadic-chat-embeddings-container`): text embeddings for search
  ```shell
  docker exec -it monadic-chat-embeddings-container bash
  ```

- **Selenium Container** (`monadic-chat-selenium-container`): browser automation
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

- **Privacy Container** (`monadic-chat-privacy-container`): personal-information detection for the Privacy Filter
  ```shell
  docker exec -it monadic-chat-privacy-container bash
  ```

- **Extractor Container** (`monadic-chat-extractor-container`): document extraction for the Knowledge Base Quality Pack (present only when installed)
  ```shell
  docker exec -it monadic-chat-extractor-container bash
  ```

## JupyterLab

**Actions → Start JupyterLab** starts JupyterLab in the Python container, in the shared folder (`/monadic/data`). Click `Terminal` on the JupyterLab Launcher to open a shell in the container. See [JupyterLab Integration](jupyterlab.md).

## Common Use Cases

### Python Container
- Install a Python package for the current container: `uv pip install --no-cache package_name` (to keep packages across rebuilds, see [Python Container](python-container.md))
- Go to the shared folder: `cd /monadic/data`
- Run your own script: `python /monadic/data/scripts/my_script.py`

### Ruby Container
- List the installed gems: `bundle list`
- Follow the server log: `tail -f /monadic/log/server.log`
- Go to the configuration folder: `cd /monadic/config`

## Related Documentation
- [Basic Architecture](basic-architecture.md) - Overview of all containers
- [Python Container](python-container.md) - Details of the Python container
