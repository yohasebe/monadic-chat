# Claude Code MCP Integration (Internal)

## Overview

This document describes the technical implementation of MCP integration between Claude Code and Monadic Chat's PGVector documentation database.

## Architecture

```
Claude Code (stdio transport)
    ↓
mcp_stdio_wrapper.rb (stdio → HTTP bridge)
    ↓
Monadic Chat MCP Server (HTTP JSON-RPC 2.0)
    ↓
Monadic Help App Tools
    ↓
PGVector Database (3072-dim embeddings)
```

## Components

### 1. MCP Server (`docker/services/ruby/lib/monadic/mcp/server.rb`)

**Key Features:**
- Sinatra-based HTTP server on port 3100
- JSON-RPC 2.0 protocol implementation
- Automatic tool discovery from all apps
- 5-minute TTL cache for tool list
- Direct app instance lookup for O(1) tool execution

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

### 2. Stdio Wrapper (`~/monadic/scripts/mcp_stdio_wrapper.rb`)

**Purpose:**
Bridges the transport protocol mismatch:
- Claude Code: stdio (reads STDIN, writes STDOUT)
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
- `MCP_SERVER_URL`: Override default http://localhost:3100/mcp
- `DEBUG=true`: Write debug logs to /tmp/mcp_wrapper.log

**Error Handling:**
- JSON parse errors → -32700 (Parse error)
- Network errors → -32603 (Internal error)
- All errors logged with timestamps when DEBUG=true

### 3. Monadic Help App (`docker/services/ruby/apps/monadic_help/`)

**Exposed Tools:**
1. `find_help_topics` - Semantic search with PGVector
2. `get_help_document` - Retrieve full document by ID
3. `list_help_sections` - List all sections
4. `search_help_by_section` - Section-scoped search

**PGVector Integration:**
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

### Client-Side (Claude Code)

**Global configuration:**
```bash
claude mcp add --scope user --transport stdio monadic-chat \
  --env DEBUG=true \
  -- ruby /Users/yohasebe/monadic/scripts/mcp_stdio_wrapper.rb
```

**Configuration stored in:**
- `~/.claude.json` (user scope)
- Or `.claude/settings.local.json` (project scope)

**Verification:**
```bash
# List configured servers
claude mcp list

# Check specific server details
claude mcp get monadic-chat

# Remove server if needed
claude mcp remove monadic-chat -s user
```

## Tool Discovery Flow

1. **Claude Code starts session**
   - Launches stdio wrapper subprocess
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

4. **Tool list returned to Claude Code**
   - `MonadicHelpOpenAI__find_help_topics`
   - `MonadicHelpOpenAI__get_help_document`
   - etc.

## Tool Execution Flow

1. **Claude Code decides to call tool**
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

4. **Tool executes against PGVector**
   - Generates embedding for query text
   - Searches PostgreSQL with pgvector extension
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

**PGVector Queries:**
- Embedding generation: ~100ms (OpenAI API call)
- Vector similarity search: ~10ms (indexed)
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

**"Server not connected" in Claude Code:**
- Check Monadic Chat server is running: `curl http://localhost:3100/health`
- Verify wrapper script exists: `ls -la ~/monadic/scripts/mcp_stdio_wrapper.rb`
- Check wrapper permissions: `chmod +x ~/monadic/scripts/mcp_stdio_wrapper.rb`

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

Claude Code only supports stdio transport for MCP servers, while Monadic Chat's MCP server uses HTTP transport for these reasons:

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

The standard `rake help:build` command now includes internal documentation by default:

```bash
# Build VectorDB with both public and internal docs
rake help:build

# Or rebuild from scratch
rake help:rebuild
```

**What happens during build:**
1. Processes `docs/` (public documentation)
2. Processes `docs_dev/` (internal documentation)
3. Stores both in local PGVector database with `is_internal` flag
4. **Exports only public docs** for packaging (internal docs filtered out)

### Export Safety Mechanism

The export process (`export_help_database_docker.rb`) automatically filters internal documentation:

```ruby
# Line 146: Only export public documents
SELECT * FROM help_docs WHERE is_internal = FALSE

# Line 186: Only export public items
SELECT hi.* FROM help_items hi
JOIN help_docs hd ON hi.doc_id = hd.id
WHERE hd.is_internal = FALSE
```

**Result:**
- **Developers**: Local database contains all documentation
- **End Users**: Packaged app contains only public documentation
- **MCP Access**: Developers can search all docs, users can search only public docs

### Deprecated Task

`rake help:build_dev` is now deprecated and redirects to `rake help:build`:

```bash
# This now shows a deprecation warning and calls rake help:build
rake help:build_dev
```

### Known Limitations

1. **Latency**: stdio wrapper adds ~50ms overhead
2. **No Streaming**: Results returned after completion only
3. **Error Context**: Limited error details in Claude Code UI
4. **Cache Invalidation**: Manual restart required to clear tool cache

## Related Documentation

- **Public Documentation**: `docs/advanced-topics/mcp-integration.md`
- **MCP Server Code**: `docker/services/ruby/lib/monadic/mcp/server.rb`
- **Monadic Help App**: `docker/services/ruby/apps/monadic_help/`
- **PGVector Integration**: `docs_dev/ruby_service/help_embeddings.md`
