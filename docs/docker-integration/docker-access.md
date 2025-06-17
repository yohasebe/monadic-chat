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

- **PostgreSQL/pgvector Container** (`monadic-chat-pgvector-container`): Vector database for RAG
  ```shell
  docker exec -it monadic-chat-pgvector-container bash
  ```

- **Selenium Container** (`monadic-chat-selenium-container`): Web scraping and browser automation
  ```shell
  docker exec -it monadic-chat-selenium-container bash
  ```

- **Ollama Container** (`monadic-chat-ollama-container`): Local LLM support (when built)
  ```shell
  docker exec -it monadic-chat-ollama-container bash
  ```

?> **Development Tip**: When developing locally, you can stop the Ruby container and run the application on your host machine while keeping other containers running. See [Development Workflow](../developer/development_workflow.md) for details.

## JupyterLab

By using the `Actions/Start JupyterLab` menu in the Monadic Chat console, you can start JupyterLab, which will launch with `/monadic/data` as the current directory on the Python container. By clicking `Terminal` on the JupyterLab Launcher screen, you can access the Python container.

![JupyterLab Terminal](../assets/images/jupyterlab-terminal.png ':size=600')

## Common Use Cases

### Python Container
- Install additional Python packages: `pip install package_name`
- Access shared data: `cd /monadic/data`
- Run Python scripts: `python /monadic/data/scripts/my_script.py`

### PostgreSQL Container
- Access database: `psql -U postgres`
- List databases: `psql -U postgres -l`
- Access monadic_chat database: `psql -U postgres -d monadic_chat`

### Ruby Container
- Check Ruby gems: `bundle list`
- View logs: `tail -f /monadic/logs/sinatra.log`
- Access configuration: `cd /monadic/config`

## Related Documentation
- [Basic Architecture](basic-architecture.md) - Overview of all containers
- [Python Container](python-container.md) - Detailed Python container documentation
- [Development Workflow](../developer/development_workflow.md) - Development setup and tips
