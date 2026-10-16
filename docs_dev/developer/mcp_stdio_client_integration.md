# MCP Server and Stdio Bridge (Internal)

Monadic Chat's MCP server (Monadic Conduit) publishes a fixed set of `monadic_*` tools over HTTP JSON-RPC 2.0. Clients that speak only the stdio transport use `scripts/mcp_stdio_bridge.rb`. The public description of the tools is `docs/advanced-topics/mcp-integration.md`.

```
MCP client (stdio)  →  mcp_stdio_bridge.rb  →  POST http://127.0.0.1:3100/mcp  →  Monadic::MCP::Server  →  Monadic::MCP::Conduit
MCP client (HTTP)   →  POST http://127.0.0.1:3100/mcp  →  …
```

## Server (`lib/monadic/mcp/server.rb`)

- Starts only when `MCP_SERVER_ENABLED` is true; port `MCP_SERVER_PORT` (default 3100).
- `MCPServerStarter` in `config.ru` calls `Monadic::MCP::Server.start!` on the first request a Falcon worker handles, once the Async reactor runs. If the port is already in use, start-up is skipped with `[MCP] MCP Server port … is already in use`.
- Binds `0.0.0.0` inside the container (compose publishes the port on the host's `127.0.0.1` only) and `127.0.0.1` in development mode.
- `LocalOriginGuard` (mode `:api`) refuses any request that carries an `Origin` header, which every browser page request does. POST bodies must be `application/json` (otherwise 415).
- Routes: `GET /health`, `POST /mcp`.

JSON-RPC methods:

| Method | Handler | Does |
|---|---|---|
| `initialize` | `handle_initialize` | Server info and capabilities |
| `tools/list` | `handle_tools_list` | `Monadic::MCP::Conduit.tools` |
| `tools/call` | `handle_tool_call` | `Conduit.call(name, arguments)` for a known tool, otherwise an error |

The tool list is static (not derived from the apps): status and models, queries to one or several providers, second opinion and confidence, Knowledge Base search, list and import, media analysis and transcription, speech, code, image, video and music generation, a bounded tool-using agent (`monadic_agent`), and background jobs (`monadic_submit`, kept by the job store). The definitions are in `lib/monadic/mcp/conduit.rb`; `cost_guard.rb` keeps a process-wide token budget that each token-spending tool reserves against before the call and settles after it, and `job_store.rb` keeps background jobs.

## Stdio Bridge (`scripts/mcp_stdio_bridge.rb`)

Self-contained (Ruby standard library only), run by the host's `ruby`:

```bash
ruby /path/to/monadic-chat/docker/services/ruby/scripts/mcp_stdio_bridge.rb
```

- Reads one JSON-RPC message per line from stdin, posts it to `http://MCP_SERVER_HOST:MCP_SERVER_PORT/mcp` (defaults `127.0.0.1`, `3100`) and writes the response as one line on stdout.
- A notification (no `id`) gets no reply.
- Errors: unparsable input → `-32700`; connection or HTTP errors → `-32603`, with the request's `id`.
- Timeouts: open 5 seconds, read 600 seconds.

Clients that speak streamable HTTP can use `http://127.0.0.1:3100/mcp` directly. The endpoint answers a notification, or a batch of notifications only, with 202 and no body; `ping` with an empty result; a batch with an array of the replies; an empty batch, or an element that is not a request, with `-32600`; `params` or `arguments` that are present and not objects with `-32602`; a JSON-RPC response from the client with 202; and `GET` with 405 (there is no server-to-client stream). How a client registers a server is client-specific.

## Configuration

`~/monadic/config/env`:

```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
EXTRA_LOGGING=true   # optional: [MCP] log lines
```

## Checking by Hand

```bash
curl http://localhost:3100/health

curl -X POST http://localhost:3100/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | jq .

curl -X POST http://localhost:3100/mcp -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"monadic_status","arguments":{}}}' | jq .
```

| Symptom | Check |
|---|---|
| Client reports the server is not connected | The app is running with `MCP_SERVER_ENABLED=true`; `curl http://localhost:3100/health`; the bridge path is right |
| A request from a browser page is refused | Intended: requests with an `Origin` header are refused |
| A tool fails | The `rake server:debug` output (with `EXTRA_LOGGING=true`) |

## Help Database Build

The Help database (used by the Monadic Chat Help app) is built from the documentation:

| Task | Builds |
|---|---|
| `rake help:build` | `docs/` only (`--public-only`); this is the dump that ships |
| `rake help:rebuild` | The same, from scratch |
| `rake help:build_internal` | `docs/` plus `docs_dev/` (`is_internal=true`), for local development |

All write `help_data/help_db.json`; the last run is the dump on disk. `scripts/help_dump_guard.rb` stops packaging when the dump contains an `is_internal` point; it runs from `scripts/stage_docker_payload.rb` (Rake builds) and from `scripts/before_pack.js` (electron-builder). At search time `is_internal` is a Qdrant payload filter: with `DEBUG_MODE=true` both trees are returned, otherwise only `docs/`. See [Internal Documentation in the Monadic Help Database](help_system_internal.md).

## Related Files

- `docker/services/ruby/lib/monadic/mcp/server.rb`, `conduit.rb`, `conduit_agent.rb`, `cost_guard.rb`, `job_store.rb`
- `docker/services/ruby/scripts/mcp_stdio_bridge.rb`
- `docs/advanced-topics/mcp-integration.md`
