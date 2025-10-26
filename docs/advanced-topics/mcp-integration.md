# MCP (Model Context Protocol) Integration

## Overview

Monadic Chat implements a Model Context Protocol (MCP) server that exposes all app tools via a standard JSON-RPC 2.0 interface. This enables AI assistants and other MCP clients to access Monadic Chat functionality programmatically.

## Configuration

Enable the MCP server by adding the following to `~/monadic/config/env`:

```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

## Protocol Details

- **Version**: 2025-06-18
- **Transport**: HTTP (JSON-RPC 2.0)
- **Endpoint**: `http://localhost:3100/mcp`
- **Server Name**: monadic-chat

## Automatic Tool Discovery

The MCP server automatically discovers and exposes all tools from Monadic Chat apps:

- New apps are automatically detected when added
- No additional configuration required
- Tools are discovered from app settings at runtime
- Tool naming convention: `AppName__tool_name`

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
    "name": "MonadicHelpOpenAI__find_help_topics",
    "arguments": {
      "text": "voice chat"
    }
  }
}
```

## Example Tools

- `PDFNavigatorOpenAI__find_closest_text` - Find closest text in PDF documents
- `CodeInterpreterOpenAI__run_code` - Execute code
- `ImageGeneratorOpenAI__generate_image_with_openai` - Generate images
- `MonadicHelpOpenAI__find_help_topics` - Search help documentation
- `SyntaxTreeOpenAI__render_syntax_tree` - Create syntax tree diagrams
- `MermaidGrapherOpenAI__validate_mermaid_syntax` - Validate Mermaid diagram syntax

Each tool includes:
- `name`: Unique identifier
- `description`: Human-readable description
- `inputSchema`: JSON Schema defining parameters

## Client Implementation Example

A complete example client is available at:
```bash
ruby docker/services/ruby/scripts/mcp_client_example.rb "search query"
```

Basic client implementation:
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
    
    response = http.request(req)
    JSON.parse(response.body)
  end
end
```

## Performance

The MCP server includes performance optimizations:
- 5-minute TTL cache for tool discovery
- Direct app lookup for tool execution (O(1) complexity)
- Cache automatically invalidated when apps are reloaded

## Error Handling

The server uses standard JSON-RPC 2.0 error codes:
- `-32700`: Parse error
- `-32600`: Invalid request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

Error responses include helpful details:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Parameter error: missing keyword: text",
    "data": "Required parameters: text\nOptional parameters: top_n\nProvided parameters: query"
  }
}
```

## Security

- Server binds to localhost only (127.0.0.1)
- No authentication required (localhost only)
- CORS headers configured for browser-based clients

## Known Limitations

- Resources and prompts methods not implemented
- Some MCP clients may have compatibility issues with the standard implementation