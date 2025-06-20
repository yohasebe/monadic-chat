# Claude Code MCP Setup Guide

## Prerequisites
1. Ensure Monadic Chat is running with MCP server enabled
2. Verify MCP server is accessible at http://localhost:3100/mcp

## Configuration Steps

### Method 1: HTTP Transport (Recommended)

1. Run the following command to add the MCP server:
```bash
claude mcp add monadic-chat-help http http://localhost:3100/mcp
```

2. Verify configuration:
```bash
claude mcp list
```

### Method 2: Stdio Transport

1. Ensure the stdio server script is executable:
```bash
chmod +x /Users/yohasebe/code/monadic-chat/docker/services/ruby/bin/mcp_stdio_server.rb
```

2. Add the MCP server:
```bash
claude mcp add monadic-chat-help stdio /Users/yohasebe/code/monadic-chat/docker/services/ruby/bin/mcp_stdio_server.rb
```

### Manual Configuration (Alternative)

If the CLI commands don't work, you can manually edit the Claude Code configuration:

1. Find Claude Code's configuration directory (usually ~/.claude/ or similar)
2. Edit the MCP configuration file to add:

For HTTP:
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "transport": "http",
      "url": "http://localhost:3100/mcp"
    }
  }
}
```

For Stdio:
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "transport": "stdio",
      "command": "/Users/yohasebe/code/monadic-chat/docker/services/ruby/bin/mcp_stdio_server.rb"
    }
  }
}
```

## Verification

1. Restart Claude Code if it's running
2. Check available MCP tools:
```bash
claude mcp list
```

You should see:
- monadic-chat-help (3 tools available)

## Available Tools

Once connected, you can use these tools:
- `monadic_help_search` - Search Monadic Chat documentation
- `monadic_help_get_categories` - List all help categories
- `monadic_help_get_by_category` - Get items from specific category

## Troubleshooting

### "No MCP servers configured"
- Ensure you've run the `claude mcp add` command
- Try restarting Claude Code
- Check if ~/.claude/config exists

### Connection refused
- Verify Monadic Chat is running
- Check MCP_SERVER_ENABLED=true in ~/monadic/config/env
- Confirm port 3100 is not blocked

### Permission denied (stdio mode)
- Make stdio server executable: `chmod +x /path/to/mcp_stdio_server.rb`
- Check Ruby is in PATH

### HTTP connection issues
- Test with curl: `curl -X POST http://localhost:3100/mcp -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'`
- Check for proxy settings that might interfere