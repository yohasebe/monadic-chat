# Using Ollama

## Setup

Ollama is now built into Monadic Chat as an optional feature. To use Ollama:

1. Make sure Monadic Chat is stopped (Actions → Stop)
2. Go to Actions → Build Ollama Container (this is separate from "Build All")
3. Wait for the build to complete (this may take several minutes on first build)
4. Start Monadic Chat (Actions → Start)
5. You should now see the "Chat" app in the Ollama group

!> The Ollama container is not built automatically with "Build All" to save resources. You must explicitly choose "Build Ollama Container" to use this feature.

## Adding Language Models

### Using olsetup.sh (Recommended)

You can automate model installation by creating an `olsetup.sh` file in your config directory:

1. Create `~/monadic/config/olsetup.sh` with your desired models:

```bash
#!/bin/bash
# Example olsetup.sh - Install models

echo "Installing Ollama models..."

# Install your desired models
ollama pull llama3.2:3b
ollama pull gemma2:2b
ollama pull mistral:7b

# Add more models as needed
# ollama pull model-name:size

echo "Model installation complete!"
```

2. Make it executable:
```bash
chmod +x ~/monadic/config/olsetup.sh
```

3. Build the Ollama container (Actions → Build Ollama Container)

The models will be automatically installed during the container build process and stored in `~/monadic/ollama/` for persistence.

!> **Important**: When using `olsetup.sh`, only the models specified in the script will be installed. The default model (defined by `OLLAMA_DEFAULT_MODEL` configuration variable or `llama3.2` if not set) will NOT be automatically installed. If you want the default model, you must explicitly include it in your script.

### Manual Installation

If no `olsetup.sh` is found, the system will automatically pull `llama3.2` as a default. You can change the default model by setting the `OLLAMA_DEFAULT_MODEL` configuration variable in your `~/monadic/config/env` file.

To manually add more models, connect to the Ollama container from your terminal:

```shell
$ docker exec -it monadic-chat-ollama-container bash
$ ollama run gemma2:2b
pulling manifest
pulling 7462734796d6... 100% ▕████████████▏ 1.6 GB
pulling e0a42594d802... 100% ▕████████████▏  358 B
pulling 097a36493f71... 100% ▕████████████▏ 8.4 KB
pulling 2490e7468436... 100% ▕████████████▏   65 B
pulling e18ad7af7efb... 100% ▕████████████▏  487 B
verifying sha256 digest
writing manifest
success
>>>
```

After the model finishes downloading, you'll see an interactive Ollama shell prompt (`>>>`). Type `/bye` to exit the shell.

The models you've added will be available for selection in the "Chat" app (Ollama version).

!> Loading locally downloaded models into the Docker container can take some time. Reload the web interface if the model doesn't appear immediately, especially after adding a new model or restarting Monadic Chat.

## Technical Details

- **Model Storage**: All models are stored in `~/monadic/ollama/` on your host machine for persistence
- **Default Model**: `OLLAMA_DEFAULT_MODEL` configuration variable specifies which model to download during build when no `olsetup.sh` exists (default: `llama3.2`)
- **Model Selection**: The web UI automatically selects the first available model from the Ollama service
- **Model List**: The app dynamically checks for available models when the Ollama service is running
- **Container Management**: Uses Docker profiles for conditional building (profile: `ollama`)
