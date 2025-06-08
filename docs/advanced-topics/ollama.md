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
# Example olsetup.sh - Install default models

echo "Installing Ollama models..."

# Install recommended models
ollama pull llama3.2:3b
ollama pull gemma2:2b
ollama pull mistral:7b

# Add any other models you want
# ollama pull phi3:3.8b
# ollama pull qwen2.5:3b

echo "Model installation complete!"
```

2. Make it executable:
```bash
chmod +x ~/monadic/config/olsetup.sh
```

3. Build the Ollama container (Actions → Build Ollama Container)

The models will be automatically installed during container startup and stored in `~/monadic/ollama/` for persistence.

### Manual Installation

If no `olsetup.sh` is found, the system will automatically pull `llama3.2` as a default. You can change the default model by setting the `OLLAMA_DEFAULT_MODEL` environment variable in your `~/monadic/config/env` file.

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

## Popular Models

Here are some popular models you can use with Ollama, sorted by popularity and suitability for general chat:

| Model | Sizes | Description |
|-------|-------|-------------|
| **llama3.2** | 1B, 3B | Latest Llama model, good balance of performance and size |
| **llama3.1** | 8B, 70B | State-of-the-art model from Meta |
| **gemma2** | 2B, 9B, 27B | Google's lightweight models, excellent for single GPU |
| **qwen2.5** | 0.5B-72B | Alibaba's models with various size options |
| **mistral** | 7B | Fast and capable 7B model |
| **phi3** | 3.8B, 14B | Microsoft's efficient models |

For general chat purposes, we recommend starting with:
- **llama3.2:3b** (default) - Best balance of quality and speed
- **gemma2:2b** - Faster responses, good for quick interactions
- **mistral:7b** - Higher quality but requires more resources

To add any of these models, use the same process described above with `ollama run [model-name]`.

!> Loading locally downloaded models into the Docker container can take some time. Reload the web interface if the model doesn't appear immediately, especially after adding a new model or restarting Monadic Chat.

## Technical Details

- **Model Storage**: All models are stored in `~/monadic/ollama/` on your host machine for persistence
- **Default Model**: Configurable via `OLLAMA_DEFAULT_MODEL` environment variable (default: `llama3.2:latest`)
- **Model List**: The app dynamically checks for available models when the Ollama service is running
- **Container Management**: Uses Docker profiles for conditional building (profile: `ollama`)
