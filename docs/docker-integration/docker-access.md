# Accessing Docker Containers

There are two ways to access a Docker container.

## Docker Command

To access a Docker container, use the `docker exec` command. The following containers are available:

When you start Monadic Chat, the availability of each container is displayed in the main window console.

### Available Containers

- **Ruby Container** (`monadic-chat-ruby-container`): Main application container
  ```shell
  docker exec -it monadic-chat-ruby-container bash
  ```

- **Python Container** (`monadic-chat-python-container`): Code execution and data analysis
  ```shell
  docker exec -it monadic-chat-python-container bash
  ```

- **Qdrant Container** (`monadic-chat-qdrant-container`): Vector database for RAG (PDF + help)
  ```shell
  docker exec -it monadic-chat-qdrant-container sh
  ```

- **Embeddings Container** (`monadic-chat-embeddings-container`): Local `multilingual-e5-base` inference for RAG queries
  ```shell
  docker exec -it monadic-chat-embeddings-container bash
  ```

- **Selenium Container** (`monadic-chat-selenium-container`): Web scraping and browser automation
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

?> **Development Tip**: When developing locally, you can stop the Ruby container and run the application on your host machine while keeping other containers running.

## JupyterLab

By using the `Actions/Start JupyterLab` menu in the Monadic Chat console, you can start JupyterLab, which will launch with `/monadic/data` as the current directory on the Python container. By clicking `Terminal` on the JupyterLab Launcher screen, you can access the Python container.

<!-- SCREENSHOT: JupyterLab terminal window showing command prompt at /monadic/data directory -->

## Common Use Cases

### Python Container
- Install additional Python packages:
  - `uv pip install --no-cache package_name` (recommended)
  - `pip install package_name`
- Access shared data: `cd /monadic/data`
- Run Python scripts: `python /monadic/data/scripts/my_script.py`

### Qdrant Container
- List collections: `curl http://localhost:6333/collections` (from host in dev mode)
- Inspect a collection: `curl http://localhost:6333/collections/help_docs`
- Open the built-in Web UI in a browser: `http://localhost:6333/dashboard` (dev mode only)

### Embeddings Container
- Health probe: `curl http://localhost:8002/v1/health` (from host in dev mode)
- Model info: `curl http://localhost:8002/v1/info`

### Ruby Container
- Check Ruby gems: `bundle list`
- View logs: `tail -f /monadic/log/server.log`
- Access configuration: `cd /monadic/config`

## Related Documentation
- [Basic Architecture](basic-architecture.md) - Overview of all containers
- [Python Container](python-container.md) - Detailed Python container documentation
