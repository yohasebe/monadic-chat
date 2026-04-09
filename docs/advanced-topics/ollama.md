# Using Ollama

## Setup

Monadic Chat connects directly to Ollama running on your host machine. This provides full GPU acceleration (Metal on macOS, CUDA on Linux) and eliminates the need for a separate Docker container.

### 1. Install Ollama

Download and install Ollama for your operating system:

- **macOS**: [Download from ollama.com](https://ollama.com/download/mac)
- **Windows**: [Download from ollama.com](https://ollama.com/download/windows)
- **Linux**: `curl -fsSL https://ollama.com/install.sh | sh`

### 2. Pull a Model

After installation, pull at least one model. A lightweight text-only starter:

```bash
ollama pull qwen3:4b
```

For a model that supports vision, tool calling, and thinking in one package:

```bash
ollama pull qwen3-vl:8b-thinking
```

You can browse available models at [Ollama Library](https://ollama.com/library). See the [Model Capabilities](#model-capabilities) section below for details on how Monadic Chat adapts to each model's features.

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

## Model Capabilities

Monadic Chat detects each Ollama model's features at runtime by querying Ollama's `/api/show` endpoint. The UI adapts automatically: the image upload button appears only for vision-capable models, the thinking panel shows only for models that expose reasoning, and tool-using apps only send tool definitions to models that support function calling.

The following capabilities are detected:

| Capability | Description | Example Models |
|------------|-------------|----------------|
| **vision** | Image input support (multimodal) | `qwen3-vl:*`, `llava`, `llama3.2-vision` |
| **tools** | Function calling for tool-enabled apps (Chat Plus, Coding Assistant) | `qwen3-vl:*`, `qwen3:*`, `llama3.1`, `mistral` |
| **thinking** | Streaming reasoning output via Ollama's `think` parameter | `qwen3-vl:*-thinking`, `qwen3:*-thinking`, `deepseek-r1:*` |
| **structured output** | JSON schema-constrained generation (supported by all models) | all |

You can inspect any model's capabilities directly with:

```bash
ollama show <model-name>
```

If Ollama is temporarily unavailable when Monadic Chat starts, the system falls back to a name-based heuristic (e.g. models with `-thinking` in the name are treated as thinking-capable).

> **Note on `-thinking` model variants**: Models with `-thinking` in the name (e.g. `qwen3-vl:8b-thinking`) always generate reasoning tokens internally, even when the Show Thinking toggle is off. This results in slower responses that cannot be avoided. For faster responses, use non-thinking variants such as `gemma4:e4b`, which can fully disable thinking when the toggle is off.

## Available Apps

The following apps are available in the Ollama group:

| App | Description |
|-----|-------------|
| **Chat** | General conversational AI assistant. Supports text and images. |
| **Coding Assistant** | Programming help with code suggestions and explanations. Supports file operations in the shared folder. |
| **Language Practice** | Language conversation practice with grammar corrections. |
| **Mail Composer** | Email drafting assistance with tone customization. Supports file operations in the shared folder. |
| **Voice Chat** | Conversational AI with voice input and output support. |

Coding Assistant and Mail Composer use tool calling for file operations. These apps require a model with the `tools` capability (see [Model Capabilities](#model-capabilities)). Chat additionally supports image input when a vision-capable model is selected.

## Technical Details

- **GPU Acceleration**: Native Ollama uses Metal (macOS) or CUDA (Linux) for hardware-accelerated inference
- **Default Model**: The default model can be configured via `OLLAMA_DEFAULT_MODEL` in `~/monadic/config/env`
- **Connection**: Monadic Chat's Ruby backend (running in Docker) connects to host Ollama via `host.docker.internal:11434`
- **Model List**: The app dynamically checks for available models when the Ollama service is running
- **Fallback**: If Ollama is not running, the app returns an error message instead of silently failing
