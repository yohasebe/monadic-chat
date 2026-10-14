# Using Ollama

## Setup

Monadic Chat connects to Ollama running on your computer, outside Docker. Ollama uses the GPU of the computer (Metal on macOS, CUDA on Linux).

### 1. Install Ollama

Download and install Ollama for your operating system:

- **macOS**: [Download from ollama.com](https://ollama.com/download/mac)
- **Windows**: [Download from ollama.com](https://ollama.com/download/windows)
- **Linux**: `curl -fsSL https://ollama.com/install.sh | sh`

### 2. Pull a Model

After installation, pull at least one model:

```bash
ollama pull <model-name>
```

Available models are listed in the [Ollama Library](https://ollama.com/library). For the tool features of Monadic Chat, choose a model with the `tools` capability; see [Model Capabilities](#model-capabilities).

### 3. Start Ollama

Ollama must be running when you use the Ollama apps. On macOS and Windows, the Ollama app starts at login. On Linux, start it yourself if it is not running:

```bash
ollama serve
```

!> **Linux users**: Ollama listens only on `127.0.0.1` by default. Monadic Chat's backend runs in a Docker container and reaches the host through `host.docker.internal`, which is not `127.0.0.1` on Linux. Start Ollama with `OLLAMA_HOST=0.0.0.0 ollama serve`, or turn on **"Expose Ollama to the network"** in the Ollama app settings. This is not needed on macOS or Windows.

### 4. Start Monadic Chat

Start Monadic Chat as usual. The Ollama apps are in the Ollama group. If Ollama is not running, the apps show an error message when you use them.

## Adding Language Models

Manage models with the `ollama` command:

```bash
# List installed models
ollama list

# Pull a model
ollama pull <model-name>

# Remove a model
ollama rm <model-name>
```

Installed models appear in the model menu of the Ollama apps. If a model you just added does not appear, reload the web interface.

## Model Capabilities :id=model-capabilities

Monadic Chat reads each model's capabilities from Ollama's `/api/show` endpoint and adapts the interface:

| Capability | What it enables |
|------------|-----------------|
| **vision** | Image input. The image button appears only for these models. |
| **tools** | Tool calling: web search and the tool features of Coding Assistant, Mail Composer and Knowledge Base. |
| **thinking** | Reasoning output, shown in the thinking panel. The Show Thinking toggle turns it on and off. |

Structured output (generation constrained by a JSON schema) works with every model.

To see a model's capabilities:

```bash
ollama show <model-name>
```

When `/api/show` gives no answer for a model, Monadic Chat guesses from the model name (for example, a name containing `thinking` is treated as a thinking model, and a name containing `vision` or `-vl` as a vision model) and treats the model as able to call tools.

?> Some models produce reasoning on every request, even when Show Thinking is off; their names often contain `thinking`. They answer more slowly. If speed matters, choose a model whose thinking can be turned off.

## Models Without Tool Calling

When the selected model does not have the `tools` capability, the sidebar shows a yellow **No tool calling** indicator. Web search and the tool features of Coding Assistant, Mail Composer and Knowledge Base do not work with that model. For plain conversation, such a model works without problems.

## Available Apps

The following apps are available in the Ollama group:

| App | Description |
|-----|-------------|
| **Chat** | General conversation. Accepts images when a vision model is selected. |
| **Coding Assistant** | Help with programming, including file operations in the shared folder. |
| **Knowledge Base** | Work with the Knowledge Base: search, list, change scope, import and delete entries. |
| **Language Practice** | Conversation practice in a foreign language, with corrections. |
| **Mail Composer** | Help with writing emails, including file operations in the shared folder. |
| **Voice Chat** | Conversation by voice. |

Coding Assistant, Mail Composer and Knowledge Base need a model with the `tools` capability.

## Technical Details

- **Default model**: Set `OLLAMA_DEFAULT_MODEL` in `~/monadic/config/env`.
- **Connection**: The backend connects to `host.docker.internal:11434`, and to `localhost:11434` when that fails.
- **Model list**: The list of models is read from Ollama while it is running and refreshed every 30 seconds.
