# Basic Architecture

Monadic Chat provides advanced features that cannot be achieved with just the language model API by incorporating a virtual environment built as a Docker container into the system.

Both users and AI agents can access the Docker container, allowing them to collaborate through natural language communication to bring about changes in the environment.

Specifically, under the user's instructions, the AI agent can install commands, teach how to use them, execute commands, and return results.

![Basic Architecture](../assets/images/basic-architecture.svg ':size=800')

## Standard Docker Containers

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

