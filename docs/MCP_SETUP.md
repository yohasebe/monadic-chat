# MCP (Model Context Protocol) Server Setup Guide

?> **Experimental Feature**: The MCP server functionality is currently experimental and may undergo significant changes in future releases. Use with caution in production environments.

## Overview
Monadic Chat now includes an MCP server that allows external AI assistants like Claude Desktop to access Monadic Chat features.

## Configuration

### 1. Enable MCP Server
Add the following to `~/monadic/config/env`:
```
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
MCP_ENABLED_APPS=help
MCP_BIND_ADDRESS=127.0.0.1  # Restrict to localhost for security
MCP_ALLOWED_ORIGINS=http://localhost:4567,http://localhost:3000  # CORS allowed origins
```

### 2. Start Monadic Chat
For development mode with PostgreSQL on port 5433:
```bash
cd /path/to/monadic-chat
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5433
rake server:debug
```

Or use the normal start command if running with Docker:
```bash
./docker/monadic.sh start
```

### 3. Verify MCP Server
Test the MCP server is running:
```bash
# Initialize
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# List tools
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

## Claude Desktop Integration

### 1. Configure Claude Desktop
Create or edit `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "command": "/path/to/monadic-chat/docker/services/ruby/bin/mcp_proxy.rb",
      "env": {
        "MCP_SERVER_URL": "http://localhost:3100/mcp",
        "MCP_DEBUG": "true"
      }
    }
  }
}
```

### 2. Restart Claude Desktop
After updating the configuration, restart Claude Desktop for the changes to take effect.

### 3. Test in Claude Desktop
In a new conversation, you should see the MCP tools available. Try:
- "Use the monadic_help.search tool to find information about PDF navigation"
- "What categories are available in Monadic Chat help?"

## Available Tools

### Monadic Help Adapter
- **monadic_help_search**: Search documentation by query (max 200 characters)
- **monadic_help_get_categories**: List all help categories  
- **monadic_help_get_by_category**: Get items from a specific category (max 100 characters)

Note: Tool names use underscores (_) instead of dots (.) for Claude Desktop compatibility.

## Troubleshooting

### MCP Server Not Starting
1. Check logs for errors about EventMachine or port conflicts
2. Ensure PostgreSQL is accessible (especially in development mode)
3. Verify MCP_SERVER_ENABLED is set to true in config

### Claude Desktop Not Connecting
1. Check Claude Desktop logs: `~/Library/Logs/Claude/`
2. Verify the proxy script has execute permissions
3. Test the proxy directly:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | \
   /path/to/monadic-chat/docker/services/ruby/bin/mcp_proxy.rb
   ```

### Database Connection Errors
In development mode, ensure PostgreSQL is running on the correct port:
```bash
docker ps | grep pgvector
# Should show port mapping like 0.0.0.0:5433->5432/tcp
```

## Development

### Adding New Adapters
1. Create adapter in `lib/monadic/mcp/adapters/`
2. Implement `list_tools`, `handles_tool?`, and `execute_tool` methods
3. Add adapter name to MCP_ENABLED_APPS in config

### Security Considerations

### Input Validation
- Query strings are limited to 200 characters
- Category names are limited to 100 characters
- Only alphanumeric characters, spaces, and common punctuation are allowed
- Invalid input will return an error message

### Network Security
- MCP server binds only to localhost (127.0.0.1)
- CORS is configured to allow only specified origins
- No authentication is required for local access
- For production use, consider implementing API key authentication

## Testing MCP Tools
```bash
# Health check
curl http://localhost:3100/health

# Test a specific tool
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"monadic_help_search",
      "arguments":{"query":"PDF navigation"}
    }
  }'
```