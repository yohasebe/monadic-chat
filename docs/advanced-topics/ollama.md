# Using Ollama

## Setup

Ollama is now built into Monadic Chat as an optional feature. To use Ollama:

1. Make sure Monadic Chat is stopped (Actions → Stop)
2. Go to Actions → Build Ollama Container (this is separate from "Build All")
3. Wait for the build to complete (this may take several minutes on first build)
4. Start Monadic Chat (Actions → Start)
5. You should now see the Ollama apps in the Ollama group

!> The Ollama container is not built automatically with "Build All" to save resources. You must explicitly choose "Build Ollama Container" to use this feature.

## Adding Language Models

### Using olsetup.sh (Recommended)

You can automate model installation by creating an `olsetup.sh` file in your config directory:

1. Create `~/monadic/config/olsetup.sh` with your desired models:

```bash
#!/bin/bash
# Example olsetup.sh - Install models
# See https://ollama.com/library for available models

echo "Installing Ollama models..."

# Install your desired models (replace with your choices)
ollama pull qwen3:4b
ollama pull gemma3:4b

# Add more models as needed
# ollama pull <model-name>:<tag>

echo "Model installation complete!"
```

2. Make it executable:
```bash
chmod +x ~/monadic/config/olsetup.sh
```

3. Build the Ollama container (Actions → Build Ollama Container)

The models will be automatically installed during the container build process and stored in `~/monadic/ollama/` for persistence.

!> **Important**: When using `olsetup.sh`, only the models specified in the script will be installed. The default model (defined by the `OLLAMA_DEFAULT_MODEL` environment variable) will NOT be automatically installed unless explicitly included in the script.

### Manual Installation

If no `olsetup.sh` is found, the system will automatically pull the default model (configurable via `OLLAMA_DEFAULT_MODEL` environment variable). You can browse available models at [Ollama Library](https://ollama.com/library).

To manually add more models, connect to the Ollama container from your terminal:

```shell
$ docker exec -it monadic-chat-ollama-container bash
$ ollama run <model-name>
```

After the model finishes downloading, you'll see an interactive Ollama shell prompt (`>>>`). Type `/bye` to exit the shell.

The models you've added will be available for selection in the Ollama apps.

!> Loading locally downloaded models into the Docker container can take some time. Reload the web interface if the model doesn't appear immediately, especially after adding a new model or restarting Monadic Chat.

## Available Apps

The following apps are available in the Ollama group:

| App | Description |
|-----|-------------|
| **Chat** | General conversational AI assistant. Supports text and images. |
| **Chat Plus** | Conversational AI with context tracking. Tracks topics, people, and notes in a sidebar panel. Also supports file operations in the shared folder. |
| **Second Opinion** | Compares responses from multiple Ollama models for the same prompt. |

Chat Plus uses tool calling to manage session context and file operations. Tool calling requires an Ollama model that supports function calling.

## Technical Details

- **Model Storage**: All models are stored in `~/monadic/ollama/` on your host machine for persistence
- **Default Model**: `OLLAMA_DEFAULT_MODEL` environment variable specifies which model to download during build when no `olsetup.sh` exists
- **Model Selection**: The web UI automatically selects the first available model from the Ollama service
- **Model List**: The app dynamically checks for available models when the Ollama service is running
- **Container Management**: Uses Docker profiles for conditional building (profile: `ollama`)
