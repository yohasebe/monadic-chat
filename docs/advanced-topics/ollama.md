# Using Ollama

## Setup

Monadic Chat connects directly to Ollama running on your host machine. This provides full GPU acceleration (Metal on macOS, CUDA on Linux) and eliminates the need for a separate Docker container.

### 1. Install Ollama

Download and install Ollama for your operating system:

- **macOS**: [Download from ollama.com](https://ollama.com/download/mac)
- **Windows**: [Download from ollama.com](https://ollama.com/download/windows)
- **Linux**: `curl -fsSL https://ollama.com/install.sh | sh`

### 2. Pull a Model

After installation, pull at least one model:

```bash
ollama pull qwen3:4b
```

You can browse available models at [Ollama Library](https://ollama.com/library).

### 3. Start Ollama

Ensure Ollama is running before starting Monadic Chat. On macOS and Windows, the Ollama app starts automatically at login. On Linux, you may need to start it manually:

```bash
ollama serve
```

!> **Linux users**: By default, Ollama only listens on `127.0.0.1` (localhost). Since Monadic Chat's backend runs inside a Docker container, it connects to the host via `host.docker.internal`, which resolves to the Docker bridge gateway IP — not `127.0.0.1`. To allow connections from Docker containers, start Ollama with `OLLAMA_HOST=0.0.0.0 ollama serve`, or enable **"Expose Ollama to the network"** in the Ollama app settings. This is not required on macOS or Windows, where Docker Desktop handles this transparently.

### 4. Start Monadic Chat

Start Monadic Chat normally. The Ollama apps will appear in the Ollama group. If Ollama is not running, the apps will show an error message when you try to use them.

## Adding Language Models

Use the `ollama` command to manage models directly on your system:

```bash
# List installed models
ollama list

# Pull a new model
ollama pull gemma3:4b

# Run a model (downloads if not present)
ollama run llama3.2

# Remove a model
ollama rm <model-name>
```

Models you install will be automatically available for selection in the Ollama apps. Reload the web interface if a newly added model does not appear immediately.

## Available Apps

The following apps are available in the Ollama group:

| App | Description |
|-----|-------------|
| **Chat** | General conversational AI assistant. Supports text and images. |
| **Chat Plus** | Conversational AI with context tracking. Tracks topics, people, and notes in a sidebar panel. Also supports file operations in the shared folder. |
| **Coding Assistant** | Programming help with code suggestions and explanations. Supports file operations in the shared folder. |
| **Language Practice** | Language conversation practice with grammar corrections. |
| **Second Opinion** | Compares responses from multiple Ollama models for the same prompt. |

Chat Plus and Coding Assistant use tool calling for file operations and other features. Tool calling requires an Ollama model that supports function calling.

## Technical Details

- **GPU Acceleration**: Native Ollama uses Metal (macOS) or CUDA (Linux) for hardware-accelerated inference
- **Default Model**: The default model can be configured via `OLLAMA_DEFAULT_MODEL` in `~/monadic/config/env`
- **Connection**: Monadic Chat's Ruby backend (running in Docker) connects to host Ollama via `host.docker.internal:11434`
- **Model List**: The app dynamically checks for available models when the Ollama service is running
- **Fallback**: If Ollama is not running, the app returns an error message instead of silently failing
