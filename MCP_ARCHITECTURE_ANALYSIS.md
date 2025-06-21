# MCP Server Architecture Analysis

## Current Architecture Overview

### 1. MCP Server Structure
The current MCP (Model Context Protocol) server implementation follows an adapter-based architecture:

```
lib/monadic/mcp/
├── server.rb              # Main JSON-RPC 2.0 server using Sinatra
├── adapters/
│   ├── help_adapter.rb    # Help search functionality
│   ├── mermaid_adapter.rb # Mermaid diagram generation
│   └── syntax_tree_adapter.rb # Syntax tree visualization
```

### 2. Key Components

#### MCP Server (`server.rb`)
- **Protocol**: JSON-RPC 2.0 over HTTP
- **Port**: 3100 (configurable)
- **Endpoints**:
  - `POST /mcp` - Main JSON-RPC endpoint
  - `GET /mcp` - SSE endpoint for server-to-client communication
  - `GET /health` - Health check endpoint
- **Features**:
  - Session management
  - Batch request support
  - Server-Sent Events (SSE)
  - EventMachine integration

#### Adapter Pattern
Each adapter:
- Implements `list_tools()` to expose available tools
- Implements `handles_tool?(tool_name)` for tool routing
- Implements `execute_tool(tool_name, arguments)` for execution
- Encapsulates domain-specific logic

### 3. Current Request Flow
1. Client sends JSON-RPC request to `/mcp`
2. Server parses request and routes to appropriate handler
3. For tool calls, server finds adapter using `find_adapter_for_tool`
4. Adapter executes tool and returns result
5. Server formats response as JSON-RPC and returns

## Pros and Cons of Current Architecture

### Pros
1. **Modularity**: Each adapter is self-contained and can be developed independently
2. **Protocol Compliance**: Follows MCP standard for AI assistant integration
3. **Extensibility**: Easy to add new adapters without modifying core server
4. **Tool Discovery**: Clients can dynamically discover available tools
5. **Session Management**: Built-in session tracking for stateful interactions
6. **Error Handling**: Structured JSON-RPC error responses

### Cons
1. **Complexity Overhead**: JSON-RPC adds parsing/formatting overhead
2. **Indirect Access**: Tools must go through MCP protocol layer
3. **Limited to MCP Clients**: Only MCP-compatible clients can use the functionality
4. **No Direct HTTP Access**: Cannot easily call tools via simple HTTP requests
5. **Adapter Duplication**: Some logic duplicated between adapters and main apps

## Alternative Approaches

### 1. Direct HTTP REST API
Create direct HTTP endpoints that bypass MCP protocol:

```ruby
# Example: Direct REST endpoints
post "/api/help/search" do
  content_type :json
  query = JSON.parse(request.body.read)["query"]
  results = HelpEmbeddings.new.search(query: query)
  results.to_json
end

post "/api/mermaid/generate" do
  content_type :json
  params = JSON.parse(request.body.read)
  # Generate Mermaid diagram directly
  generate_mermaid(params["code"], params["theme"])
end
```

**Pros**:
- Simpler for direct HTTP clients
- Lower overhead (no JSON-RPC wrapping)
- Easier to test with curl/Postman
- More RESTful

**Cons**:
- Loses MCP compatibility
- No automatic tool discovery
- Need to maintain two APIs

### 2. Hybrid Approach
Maintain MCP server but add direct HTTP endpoints that share implementation:

```ruby
# Shared implementation
module ToolImplementations
  def self.search_help(query)
    HelpEmbeddings.new.search(query: query)
  end
end

# MCP Adapter
class HelpAdapter
  def execute_tool(tool_name, arguments)
    case tool_name
    when "monadic_help_search"
      ToolImplementations.search_help(arguments["query"])
    end
  end
end

# Direct HTTP endpoint
post "/api/help/search" do
  query = JSON.parse(request.body.read)["query"]
  ToolImplementations.search_help(query).to_json
end
```

### 3. WebSocket-Based Tool Execution
Extend existing WebSocket handler to support tool execution:

```ruby
# In websocket.rb
when "TOOL_CALL"
  tool_name = obj["tool"]
  arguments = obj["arguments"]
  result = execute_tool_directly(tool_name, arguments)
  @channel.push({ "type" => "tool_result", "result" => result }.to_json)
```

### 4. GraphQL Approach
Implement a GraphQL endpoint for more flexible querying:

```ruby
# GraphQL schema
type Query {
  searchHelp(query: String!): [HelpResult!]!
  validateMermaid(code: String!): ValidationResult!
}

type Mutation {
  generateMermaid(code: String!, theme: String): GeneratedImage!
}
```

## Existing Direct Endpoints

Currently, Monadic Chat has these direct HTTP endpoints:
- `POST /load` - Load session JSON
- `POST /document` - Convert documents to text
- `POST /fetch_webpage` - Fetch webpage content
- `POST /pdf` - Upload and process PDFs
- `GET /data/:filename` - Serve generated files

These endpoints bypass any protocol layer and directly handle HTTP requests.

## Recommendations

### Short Term
1. **Keep MCP for AI Assistants**: Maintain MCP server for Claude Desktop/Code integration
2. **Add Direct Endpoints**: Create `/api/*` endpoints for commonly used tools
3. **Share Implementation**: Extract tool logic into shared modules used by both MCP and direct endpoints

### Medium Term
1. **Unified Tool Registry**: Create a central registry for all tools that can generate both MCP definitions and HTTP routes
2. **OpenAPI Documentation**: Generate OpenAPI/Swagger docs for direct HTTP endpoints
3. **Authentication**: Add API key authentication for direct endpoints

### Long Term
1. **Plugin Architecture**: Allow users to create custom tools as plugins
2. **Tool Composition**: Enable tools to call other tools
3. **Streaming Support**: Add SSE/WebSocket support for long-running operations

## Example Implementation

Here's how a unified approach might look:

```ruby
# Tool definition
class UnifiedTool
  attr_reader :name, :description, :implementation
  
  def initialize(name:, description:, &implementation)
    @name = name
    @description = description
    @implementation = implementation
  end
  
  def execute(arguments)
    @implementation.call(arguments)
  end
  
  def to_mcp
    {
      name: @name,
      description: @description,
      inputSchema: generate_schema
    }
  end
end

# Tool registry
class ToolRegistry
  def self.register(tool)
    @tools ||= {}
    @tools[tool.name] = tool
    
    # Auto-generate HTTP endpoint
    Sinatra::Application.post "/api/#{tool.name}" do
      arguments = JSON.parse(request.body.read)
      tool.execute(arguments).to_json
    end
  end
  
  def self.find(name)
    @tools[name]
  end
end

# Usage
ToolRegistry.register(
  UnifiedTool.new(
    name: "help_search",
    description: "Search help documentation"
  ) do |arguments|
    HelpEmbeddings.new.search(query: arguments["query"])
  end
)
```

This approach would provide maximum flexibility while maintaining backward compatibility.