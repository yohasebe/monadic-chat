# MCP Stdio Client Integration (Internal)

## Overview

This document describes the technical implementation behind connecting a stdio-only MCP client to Monadic Chat's Qdrant documentation database.

## Architecture

```
MCP client (stdio transport)
    ↓
mcp_stdio_bridge.rb (stdio → HTTP bridge)
    ↓
Monadic Chat MCP Server (HTTP JSON-RPC 2.0)
    ↓
Monadic Help App Tools
    ↓
Qdrant collections (768-dim embeddings from the local embeddings service)
```

## Components

### 1. MCP Server (`docker/services/ruby/lib/monadic/mcp/server.rb`)

**Architecture:**
- Runs as **Async::HTTP::Server within Falcon worker processes** (not separate process)
- Uses **Rack middleware for lazy initialization** after Async reactor starts
- Binds to port 3100 via localhost (127.0.0.1)
- Each of 8 Falcon workers runs its own MCP server instance
- Shares memory with main application (direct access to `::APPS` constant)

**Key Features:**
- JSON-RPC 2.0 protocol implementation
- Automatic tool discovery from all apps
- 5-minute TTL cache for tool list
- Direct app instance lookup for O(1) tool execution

**Startup Flow:**
1. Falcon starts and forks into 8 worker processes
2. On **first HTTP request** to main app, Rack middleware (`MCPServerStarter` in `config.ru`) executes
3. Middleware calls `Monadic::MCP::Server.start!` once per worker
4. `start!` launches `Async do` block (requires active Async reactor)
5. MCP server runs as background task on port 3100

**Important Methods:**
```ruby
def handle_tools_list(id, params)
  # Returns all tools from APPS with caching
end

def handle_tool_call(id, params)
  # Executes tool_name on app_instance
  # Format: AppName__tool_name
end
```

**Debugging:**
- All debug_log calls were replaced with `puts "[MCP] ..."` for reliability
- Enable `EXTRA_LOGGING=true` in config for detailed logs
- Check `rake server:debug` terminal for MCP-related output
- Look for `[MCP] Starting MCP Server on port 3100 in worker process <PID>...` message

### 2. Stdio Bridge (`docker/services/ruby/scripts/mcp_stdio_bridge.rb`)

**Purpose:**
Bridges the transport protocol mismatch:
- The client: stdio (reads STDIN, writes STDOUT)
- Monadic Chat: HTTP (POST to /mcp endpoint)

**Implementation:**
```ruby
# Main loop
STDIN.each_line do |line|
  request = JSON.parse(line)

  # Forward to HTTP endpoint
  result = call_mcp(request['method'], request['params'])

  # Preserve request ID for correlation
  result['id'] = request['id']

  STDOUT.puts result.to_json
  STDOUT.flush
end
```

**Environment Variables:**
- `MCP_SERVER_HOST`: Host to reach (default `127.0.0.1`)
- `MCP_SERVER_PORT`: Port to reach (default `3100`)

**Error Handling:**
- JSON parse errors → -32700 (Parse error)
- Network errors → -32603 (Internal error)
- All errors logged with timestamps when DEBUG=true

### 3. Monadic Help App (`docker/services/ruby/apps/monadic_help/`)

**Exposed Tools:**
1. `find_help_topics` - Semantic search over the Qdrant help collections
2. `get_help_document` - Retrieve full document by ID
3. `list_help_sections` - List all sections
4. `search_help_by_section` - Section-scoped search

**Search Integration:**
```ruby
def find_help_topics(text:, top_n: 10, chunks_per_result: nil, include_internal: nil)
  results = help_embeddings_db.find_closest_text_multi(
    text,
    chunks_per_result: chunks_per_result,
    top_n: top_n,
    include_internal: include_internal
  )
  # Returns grouped results by document
end
```

## Configuration

### Server-Side

**`~/monadic/config/env`:**
```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
EXTRA_LOGGING=true  # Optional: detailed MCP logs
```

**Starting the server:**
```bash
# Development mode (recommended for MCP development)
rake server:debug

# Production mode
npm start  # Electron app
```

### Client-Side

Register the bridge as a **command-based (stdio) MCP server**. Registration
syntax varies between clients, so consult the client's own documentation; the
command to run, with your host's Ruby, is:

```bash
ruby /path/to/monadic-chat/docker/services/ruby/scripts/mcp_stdio_bridge.rb
```

Clients that speak streamable-HTTP do not need the bridge at all and can point
straight at `http://localhost:3100/mcp`.

Where the registration is stored, and how to list or remove it, is also
client-specific.

## Tool Discovery Flow

1. **The client starts a session**
   - Launches the stdio bridge as a subprocess
   - Sends `initialize` request

2. **Wrapper forwards to HTTP MCP server**
   - POST http://localhost:3100/mcp
   - JSON-RPC 2.0 format

3. **MCP server calls `handle_tools_list`**
   - Checks cache (5-minute TTL)
   - If cache miss: calls `discover_apps`
   - Iterates through `::APPS` hash
   - Extracts tools from each app's settings
   - Formats tools for MCP protocol

4. **Tool list returned to the client**
   - `MonadicHelpOpenAI__find_help_topics`
   - `MonadicHelpOpenAI__get_help_document`
   - etc.

## Tool Execution Flow

1. **The client decides to call a tool**
   - Based on user query analysis
   - Selects appropriate tool and arguments

2. **Wrapper receives `tools/call` request**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 123,
     "method": "tools/call",
     "params": {
       "name": "MonadicHelpOpenAI__find_help_topics",
       "arguments": {
         "text": "MDSL syntax",
         "top_n": 5
       }
     }
   }
   ```

3. **MCP server handles tool call**
   - Parses `AppName__tool_name`
   - Direct lookup: `::APPS['MonadicHelpOpenAI']`
   - Converts arguments to symbol keys
   - Calls `app_instance.find_help_topics(**args)`

4. **Tool executes against Qdrant**
   - Embeds the query text via the local embeddings service
   - Searches the `help_items` collection with a payload filter on `is_internal`
   - Returns top N results with similarity scores

5. **Result formatted and returned**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 123,
     "result": {
       "content": [
         {
           "type": "text",
           "text": "results: [{doc_id: 1, title: ..., chunks: [...]}]"
         }
       ]
     }
   }
   ```

## Performance Considerations

### Caching Strategy

**Tool List Cache:**
- 5-minute TTL (CACHE_TTL constant)
- Cached in class variable `@@tools_cache`
- Invalidated on cache expiry or manual call to `Server.clear_cache`

**Why caching matters:**
- `discover_apps` iterates through all app instances
- Tool formatting requires schema transformation
- Typical setup: 20+ apps × 4 tools each = 80+ tools
- Cache hit: ~1ms, Cache miss: ~50ms

### Database Performance

**Search Queries:**
- Embedding generation: local `embeddings_service` container (no provider API call)
- Vector similarity search: Qdrant HNSW index
- Total latency: ~150ms for typical search

**Optimization Tips:**
- Use `chunks_per_result` to limit data transfer
- Set `top_n` appropriately (default: 10)
- Enable `include_internal: false` for external docs only

## Debugging Tips

### Enable Full Logging

1. **MCP Server Side:**
   ```bash
   # In ~/monadic/config/env
   EXTRA_LOGGING=true

   # Restart server
   rake server:debug
   ```

2. **Stdio Wrapper Side:**
   ```bash
   # Wrapper already configured with DEBUG=true
   tail -f /tmp/mcp_wrapper.log
   ```

### Common Issues

**"Server not connected" reported by the client:**
- Check Monadic Chat server is running: `curl http://localhost:3100/health`
- Verify the bridge script exists: `ls -la docker/services/ruby/scripts/mcp_stdio_bridge.rb`
- Check bridge permissions: `chmod +x docker/services/ruby/scripts/mcp_stdio_bridge.rb`

**"No tools available":**
- Check app is not disabled in settings
- Verify app has tools defined in MDSL or settings
- Clear cache: restart MCP server
- Check `rake server:debug` output for tool discovery logs

**"Tool execution failed":**
- Check error in `rake server:debug` terminal
- Verify tool method signature matches arguments
- Check PostgreSQL container is running: `docker ps | grep monadic-postgres`

### Testing MCP Server Directly

```bash
# Test initialize
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {"clientInfo": {"name": "test"}}
  }'

# Test tools/list
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }' | jq .

# Test tool call
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "MonadicHelpOpenAI__find_help_topics",
      "arguments": {"text": "test query"}
    }
  }' | jq .
```

## Implementation Notes

### Why stdio Wrapper?

Some MCP clients speak only the stdio transport, while Monadic Chat's MCP server uses HTTP transport for these reasons:

1. **Simplicity**: HTTP is stateless and easier to debug with curl
2. **Web Compatibility**: Browser-based clients can use the same endpoint
3. **Existing Infrastructure**: Monadic Chat already uses Sinatra for web UI

The stdio wrapper is a thin bridge (< 100 lines) that adds minimal overhead.

### Security Considerations

**Localhost Only:**
- MCP server binds to 127.0.0.1 only
- Not accessible from network
- No authentication required

**Stdio Wrapper:**
- Runs as user process
- Only accessible by same user
- No credential storage

## VectorDB Build Process

### Standard Build (Development)

`rake help:build` builds from `docs/` only — that is the dump that ships:

```bash
# Build the VectorDB from public docs
rake help:build

# Or rebuild from scratch
rake help:rebuild

# Local development only: also index docs_dev/
rake help:build_internal
```

**What happens during build:**
1. Processes `docs/` (public documentation) with `is_internal=false`
2. Processes `docs_dev/` (internal documentation) with `is_internal=true`,
   but only under `help:build_internal`
3. Writes the result to `help_data/help_db.json`

Both tasks write to the same path, so whichever ran last is the dump on disk.

### What ships

`help:build` passes `--public-only`, which overrides `DEBUG_MODE` — a developer
environment cannot leak internal docs into a release dump. As a second line of
defence, `scripts/help_dump_guard.rb` aborts packaging if the dump carries any
`is_internal` point, and it runs on both packaging paths: from
`scripts/stage_docker_payload.rb` on the Rake path, and from electron-builder's
`beforePack` hook for the npm build scripts, which never invoke the stager.
That catches the case where someone ran `help:build_internal` and then packaged
with `SKIP_HELP_DB=true`.

`is_internal` still acts as a Qdrant payload filter at **search** time, so on a
dump built with `help:build_internal`:

- **Developers** (`DEBUG_MODE=true`): search returns both trees
- **Everyone else**: search returns only `docs/` entries

See [Internal Documentation in the Monadic Help Database](help_system_internal.md)
for how to inspect a dump and what the distribution path actually does.

### Deprecated Task

`rake help:build_dev` is deprecated and redirects to `rake help:build_internal`:

```bash
# This shows a deprecation warning and calls rake help:build_internal
rake help:build_dev
```

### Known Limitations

1. **Latency**: stdio wrapper adds ~50ms overhead
2. **No Streaming**: Results returned after completion only
3. **Error Context**: How much error detail survives depends on the client
4. **Cache Invalidation**: Manual restart required to clear tool cache

## Related Documentation

- **Public Documentation**: `docs/advanced-topics/mcp-integration.md`
- **MCP Server Code**: `docker/services/ruby/lib/monadic/mcp/server.rb`
- **Monadic Help App**: `docker/services/ruby/apps/monadic_help/`
- **Help embeddings**: `docker/services/ruby/lib/monadic/utils/help_embeddings.rb`
