# MCP (Model Context Protocol) Integration

## Overview

Monadic Chat exposes a Model Context Protocol (MCP) server called **Monadic Conduit**. It lets MCP-compatible clients and agentic CLI tools use Monadic Chat's capabilities — multi-provider model access, a local knowledge base, audio/image/video analysis, and audio/image/video/music generation — over a standard JSON-RPC 2.0 interface.

Conduit publishes a small, stable set of capability tools in the `monadic_*` namespace. Instead of re-exposing every app's individual tools, it provides reusable building blocks and leaves orchestration to the calling client. Conduit uses your own API keys, runs locally, and keeps your data on your machine. Every tool that spends provider tokens is gated by a token budget.

## Configuration

Enable the MCP server by adding the following to `~/monadic/config/env`:

```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100

# Optional: token budget ceiling for provider-spending tools (default 1,000,000)
CONDUIT_TOKEN_BUDGET=1000000
```

In the packaged application the server runs inside the Ruby container and its port is published to the host loopback (`127.0.0.1`) only. In development mode (`rake server:debug`) it runs on the host directly.

## Protocol Details

- **Version**: 2025-06-18
- **Transport**: HTTP (JSON-RPC 2.0)
- **Endpoint**: `http://localhost:3100/mcp`
- **Health check**: `http://localhost:3100/health`
- **Server Name**: monadic-chat

## Capability Surface

Conduit exposes the following `monadic_*` tools. Each tool's full input schema is available through `tools/list`.

**Inspection (read-only, no cost)**
- `monadic_status` — backend identity, provider configuration, dependent-container readiness, and the current token budget
- `monadic_list_models` — providers, models, and their capabilities (context window, vision, tool use, etc.)

**Query**
- `monadic_query` — a single-provider, context-aware query, with optional knowledge-base grounding and privacy masking
- `monadic_parallel_query` — the same prompt sent to several providers concurrently
- `monadic_second_opinion` — verify a response by asking one or more providers to rate and critique it

**Knowledge base (local PDF knowledge base)**
- `monadic_search_kb` — semantic search over an imported knowledge base
- `monadic_list_kb` — list imported documents
- `monadic_import_kb` — import text or a PDF into a knowledge base

**Analysis (input)**
- `monadic_analyze_image` — describe or answer questions about an image
- `monadic_transcribe_audio` — speech-to-text transcription
- `monadic_analyze_audio` — qualitative analysis of audio (e.g. music critique)
- `monadic_analyze_video` — frame extraction, vision analysis, and audio transcription of a video

**Generation (output saved to the shared volume `~/monadic/data`)**
- `monadic_speak` — text-to-speech
- `monadic_generate_code` — code generation via a provider's code agent
- `monadic_generate_image` — image generation
- `monadic_generate_video` — video generation (text-to-video or image-to-video)
- `monadic_generate_music` — music generation

**Background jobs**
- `monadic_submit` — run another tool as a background job and return a job id immediately
- `monadic_poll` — check a job's status, progress, and result
- `monadic_cancel` — cancel a running job
- `monadic_jobs` — list known jobs

## Available Methods

### Initialize Session
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "your-client",
      "version": "1.0.0"
    }
  }
}
```

### List Available Tools
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

### Call a Tool
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "monadic_query",
    "arguments": {
      "provider": "openai",
      "message": "Summarize the theory of relativity in one sentence."
    }
  }
}
```

A tool result is returned as both human-readable `content` text and a machine-readable `structuredContent` object.

## Cost Control

Tools that call a provider spend tokens against a shared budget enforced by Conduit. The platform reserves the estimated cost **before** the call and refuses it if the budget would be exceeded, so a runaway client is stopped rather than trusted. The remaining budget is reported by `monadic_status` and included in each spending tool's result. The ceiling is configured with `CONDUIT_TOKEN_BUDGET` and resets when the server restarts. Knowledge-base tools use a local embeddings model and are not budget-gated.

## Background Jobs

Long-running tools — code generation, media generation, and video analysis — can be run in the background so a request does not block. Submit the tool with `monadic_submit`, then call `monadic_poll` with the returned job id to read its status, periodic progress, and final result. A running job can be stopped with `monadic_cancel`. The number of concurrently running jobs is capped.

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "monadic_submit",
    "arguments": {
      "tool": "monadic_generate_image",
      "arguments": { "prompt": "a watercolor fox" }
    }
  }
}
```

## Client Implementation Example

A minimal Ruby client:

```ruby
require 'net/http'
require 'json'

class MCPClient
  def initialize(url = "http://localhost:3100/mcp")
    @url = url
    @id = 0
  end

  def call_method(method, params = {})
    @id += 1
    request = {
      "jsonrpc" => "2.0",
      "id" => @id,
      "method" => method,
      "params" => params
    }

    uri = URI.parse(@url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path)
    req.content_type = "application/json"
    req.body = request.to_json

    JSON.parse(http.request(req).body)
  end
end

client = MCPClient.new
puts client.call_method("tools/list")
```

## Error Handling

The server uses standard JSON-RPC 2.0 error codes:
- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

Tools that fail at runtime (a missing file, a refused budget, a provider error) return a result with `success: false` and an `error` message rather than a protocol-level error.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Unknown tool: example_tool"
  }
}
```

## Security

- The server binds to the host loopback only; in the packaged app the container port is published to `127.0.0.1` and is not exposed to the local network.
- All provider calls use your own API keys, and generated files stay on your machine under `~/monadic/data`.
- The token budget is a hard ceiling that stops runaway spending.
- CORS headers are configured for browser-based clients.

## Known Limitations

- The `resources` and `prompts` MCP methods are not implemented.
- Knowledge-base tools require the Qdrant and embeddings containers.
- `monadic_analyze_video` requires the Python container for frame extraction.
- Generation and analysis tools require an API key for the relevant provider.
