# Basic Architecture

Monadic Chat runs a set of Docker containers alongside the language model APIs. The AI agent can run commands, execute code, and work with files in these containers, so it can do things that an API alone cannot.

Both you and the AI agent can use the containers. You can ask the agent in natural language to install a command, run it, and return the result.

The shared folder connects your computer and the containers: you place files there for the agent, and the agent saves the files it produces there.

![Basic Architecture](../assets/images/basic-architecture.png ':size=800')

## Local Operation :id=local-operation

- All components run on one computer: the containers, the web server, and the user interface
- Every port is bound to `127.0.0.1` (localhost), so Monadic Chat is reachable only from that computer
- Each browser tab is an independent conversation session (see [Multi-Tab Session Management](../advanced-topics/advanced-configuration.md#multi-tab-sessions))

## Standard Docker Containers :id=standard-containers

### Ruby Container (`monadic-chat-ruby-container`) :id=ruby-container
Runs the Monadic Chat server and the web interface. Every app needs it.
- **Ports**: 4567 (web interface); 3100 (MCP server, used when `MCP_SERVER_ENABLED=true`)
- **Mounted folders**: `/monadic/data` (shared folder), `/monadic/config`, `/monadic/log`

### Python Container (`monadic-chat-python-container`) :id=python-container
Runs Python code, command-line tools, and JupyterLab for the apps.
- **Port**: 8889 (JupyterLab)
- **Used by**: Code Interpreter, Jupyter Notebook, Research Assistant, Math Tutor, Video Describer, Syntax Tree, Concept Visualizer, Mermaid Grapher, DrawIO Grapher, Web Insight, Auto Forge, and Knowledge Base file imports
- Optional components (LaTeX, extra Python libraries, ImageMagick) are added with **Actions → Install Options**. See [Python Container](python-container.md).

### Selenium Container (`monadic-chat-selenium-container`) :id=selenium-container
Runs a Chromium browser that the apps control to open web pages and take screenshots.
- **Ports**: 4444 (Selenium), 7900 (browser view through **Open → Open noVNC**), 5900 (VNC)
- **Used by**: Web Insight, Research Assistant, Auto Forge, Mermaid Grapher, DrawIO Grapher

### Qdrant Container (`monadic-chat-qdrant-container`) :id=qdrant-container
Runs the [Qdrant](https://qdrant.tech) vector database. It stores the Knowledge Base, the PDF Database, and the help data. See [Vector Database](vector-database.md).

### Embeddings Container (`monadic-chat-embeddings-container`) :id=embeddings-container
Converts text into vectors with the `intfloat/multilingual-e5-base` model, for searching the Knowledge Base, the PDF Database, and the help data. It runs on the CPU and needs no API key.

### Privacy Container (`monadic-chat-privacy-container`) :id=privacy-container
Detects personal information for the [Privacy Filter](../advanced-topics/privacy-filter.md), which replaces it with placeholders before text is sent to an API. It runs locally and needs no API key.

### Extractor Container (`monadic-chat-extractor-container`) :id=extractor-container
Present only when the Knowledge Base Quality Pack is installed (**Actions → Install Options → Install Knowledge Base Quality Pack**). It extracts text from PDFs with [Docling](https://github.com/docling-project/docling), including layout analysis and OCR, when files are imported into the Knowledge Base. Without it, the Python container extracts the text of PDFs without OCR, so scanned, image-only PDFs yield no text.

## Which Apps Need Which Containers :id=container-requirements

### Minimal Setup :id=minimal-setup
These apps use only the Ruby container (plus Qdrant and Embeddings, which always run):
- Chat
- Voice Chat
- Mail Composer
- Coding Assistant
- Language Practice
- Novel Writer
- Translate

### Extended Functionality :id=extended-functionality

**Python Container**:
- Code execution (Code Interpreter, Jupyter Notebook)
- Diagrams with LaTeX (Syntax Tree, Concept Visualizer)
- Video analysis (Video Describer)
- Knowledge Base file imports (PDF and Office files)

**Selenium Container**:
- Opening web pages and taking screenshots (Web Insight, Research Assistant, Auto Forge)
- Diagram previews (Mermaid Grapher, DrawIO Grapher)

**Qdrant + Embeddings Containers**:
- Knowledge Base
- PDF Database
- Monadic Chat Help

?> To add your own containers, see [Adding Docker Containers](../advanced-topics/adding-containers.md).

## Ollama Integration (Native) :id=ollama-integration

Monadic Chat can use [Ollama](https://ollama.com) for local LLMs. Ollama runs on your computer, not in a container, and uses its GPU (Metal on macOS, CUDA on Linux and Windows). Install it from [https://ollama.com/download](https://ollama.com/download) and download models with `ollama pull <model>`. See [Using Ollama](../advanced-topics/ollama.md).

## Container Network Architecture :id=network-architecture

### Network Configuration :id=network-configuration
- **Network name**: `monadic-chat-network` (bridge)
- Containers reach one another by container name

### Container Startup :id=container-dependencies
- When you press Start, Monadic Chat starts the Ruby, Python, Selenium, Qdrant, Embeddings, and Privacy containers, and the Extractor container when it is installed
- The web interface opens as soon as the Ruby container is ready; the Knowledge Base and help search become available when Qdrant and Embeddings have finished starting (the first start takes longer while the embedding model loads). Help search also needs the help data, installed from **Help Data** in the Monadic Chat Info panel
- If a container an app needs has stopped, Monadic Chat starts it again when you select the app

### Shared Data Volumes :id=shared-volumes
- **Shared folder**: `~/monadic/data` is mounted at `/monadic/data` in the Ruby, Python, Selenium, and Extractor containers
- **Configuration and logs**: `/monadic/config` and `/monadic/log` are mounted only in the Ruby container
- Qdrant keeps its data in the Docker volume `monadic-chat-qdrant-data`

## Updates and Rebuilds :id=rebuilding-process

- After an app update, the first Start rebuilds the Ruby container (this reuses the build cache, so it is quick) and updates the other containers whose definitions changed in the update
- **Actions → Build Ruby Container** and **Actions → Build Python Container** rebuild from scratch, without the cache
- Start reports its progress in the console. A summary of each start is written to `~/monadic/log/docker_startup.log`

## Startup Health Check :id=startup-health

At Start, Monadic Chat waits until the Ruby container reports that it is healthy. If it reports a failure, Monadic Chat rebuilds the Ruby container once and starts it again; the console then shows this as an informational message.

- How long it waits is set by `START_HEALTH_TRIES` (default `20`) and `START_HEALTH_INTERVAL` (seconds, default `2`) in `~/monadic/config/env`
- `FORCE_RUBY_REBUILD_NO_CACHE=true` in `~/monadic/config/env` makes every Ruby rebuild skip the cache
