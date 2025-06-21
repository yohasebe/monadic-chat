# Example: Direct HTTP Endpoint Implementation
# This shows how direct HTTP endpoints could work alongside MCP

# 1. Shared Tool Implementation Module
module DirectToolImplementations
  # Help search implementation
  def self.search_help(query, num_results: 3)
    return { error: "Query is required" } if query.nil? || query.strip.empty?
    return { error: "Query too long (max 200 characters)" } if query.length > 200
    
    # Initialize help embeddings
    help_db = HelpEmbeddings.new
    
    # Search for relevant content
    results = help_db.search(
      query: query,
      num_results: num_results
    )
    
    # Format results
    {
      success: true,
      query: query,
      results: results.map do |r|
        {
          title: r[:title],
          content: r[:content],
          category: r[:metadata]&.dig("category"),
          relevance_score: (1 - r[:distance]).round(3)
        }
      end
    }
  end
  
  # Mermaid diagram generation
  def self.generate_mermaid(code, theme: "default")
    return { error: "Code is required" } if code.nil? || code.strip.empty?
    
    timestamp = Time.now.to_i.to_s
    filename = "mermaid_#{timestamp}.png"
    output_path = File.join(SHARED_VOL, filename)
    
    # Execute mermaid generation (simplified)
    result = execute_mermaid_generation(code, theme, output_path)
    
    if result[:success]
      {
        success: true,
        filename: filename,
        url: "/data/#{filename}",
        theme: theme
      }
    else
      {
        success: false,
        error: result[:error]
      }
    end
  end
  
  # Syntax tree generation
  def self.generate_syntax_tree(sentence, format: "tree")
    return { error: "Sentence is required" } if sentence.nil? || sentence.strip.empty?
    
    timestamp = Time.now.to_i.to_s
    filename = "syntax_tree_#{timestamp}.svg"
    output_path = File.join(SHARED_VOL, filename)
    
    # Execute syntax tree generation
    result = execute_syntax_tree_generation(sentence, format, output_path)
    
    if result[:success]
      {
        success: true,
        filename: filename,
        url: "/data/#{filename}",
        format: format
      }
    else
      {
        success: false,
        error: result[:error]
      }
    end
  end
  
  private
  
  def self.execute_mermaid_generation(code, theme, output_path)
    # Implementation would go here
    # This would use the same logic as the MCP adapter
    { success: true }
  end
  
  def self.execute_syntax_tree_generation(sentence, format, output_path)
    # Implementation would go here
    # This would use the same logic as the MCP adapter
    { success: true }
  end
end

# 2. Direct HTTP Endpoints (in monadic.rb or separate file)
# These would be added to the Sinatra application

# API endpoint for help search
post "/api/help/search" do
  content_type :json
  
  begin
    # Parse request body
    request_data = JSON.parse(request.body.read)
    
    # Call shared implementation
    result = DirectToolImplementations.search_help(
      request_data["query"],
      num_results: request_data["num_results"] || 3
    )
    
    result.to_json
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON in request body" }.to_json
  rescue => e
    { success: false, error: "Internal error: #{e.message}" }.to_json
  end
end

# API endpoint for Mermaid generation
post "/api/mermaid/generate" do
  content_type :json
  
  begin
    request_data = JSON.parse(request.body.read)
    
    result = DirectToolImplementations.generate_mermaid(
      request_data["code"],
      theme: request_data["theme"] || "default"
    )
    
    result.to_json
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON in request body" }.to_json
  rescue => e
    { success: false, error: "Internal error: #{e.message}" }.to_json
  end
end

# API endpoint for Syntax Tree generation
post "/api/syntax_tree/generate" do
  content_type :json
  
  begin
    request_data = JSON.parse(request.body.read)
    
    result = DirectToolImplementations.generate_syntax_tree(
      request_data["sentence"],
      format: request_data["format"] || "tree"
    )
    
    result.to_json
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON in request body" }.to_json
  rescue => e
    { success: false, error: "Internal error: #{e.message}" }.to_json
  end
end

# 3. Updated MCP Adapters to use shared implementations
# This shows how MCP adapters would be refactored to use the same logic

module Monadic
  module MCP
    module Adapters
      class HelpAdapter
        def execute_tool(tool_name, arguments)
          case tool_name
          when "monadic_help_search"
            # Use shared implementation
            result = DirectToolImplementations.search_help(arguments["query"])
            
            # Format for MCP response
            if result[:success]
              {
                content: [
                  {
                    type: "text",
                    text: format_search_results(result[:results], result[:query])
                  }
                ]
              }
            else
              { error: result[:error] }
            end
          # ... other tools
          end
        end
      end
    end
  end
end

# 4. Unified Tool Registry (future enhancement)
class UnifiedToolRegistry
  @tools = {}
  
  class Tool
    attr_reader :name, :description, :parameters, :implementation
    
    def initialize(name:, description:, parameters:, &implementation)
      @name = name
      @description = description
      @parameters = parameters
      @implementation = implementation
    end
    
    def execute(args)
      @implementation.call(args)
    end
    
    # Generate MCP tool definition
    def to_mcp
      {
        name: @name,
        description: @description,
        inputSchema: {
          type: "object",
          properties: @parameters,
          required: @parameters.keys.select { |k| @parameters[k][:required] }
        }
      }
    end
    
    # Generate OpenAPI schema
    def to_openapi
      {
        operationId: @name,
        summary: @description,
        requestBody: {
          required: true,
          content: {
            "application/json" => {
              schema: {
                type: "object",
                properties: @parameters,
                required: @parameters.keys.select { |k| @parameters[k][:required] }
              }
            }
          }
        }
      }
    end
  end
  
  def self.register(tool)
    @tools[tool.name] = tool
    
    # Auto-generate HTTP endpoint
    Sinatra::Application.post "/api/tools/#{tool.name}" do
      content_type :json
      
      begin
        args = JSON.parse(request.body.read)
        result = tool.execute(args)
        result.to_json
      rescue => e
        { success: false, error: e.message }.to_json
      end
    end
  end
  
  def self.list_tools
    @tools.values
  end
  
  def self.find(name)
    @tools[name]
  end
  
  # Generate OpenAPI documentation
  def self.generate_openapi_spec
    {
      openapi: "3.0.0",
      info: {
        title: "Monadic Chat Direct API",
        version: "1.0.0"
      },
      paths: @tools.transform_values do |tool|
        {
          post: tool.to_openapi
        }
      end.transform_keys { |k| "/api/tools/#{k}" }
    }
  end
end

# 5. Example usage of unified registry
UnifiedToolRegistry.register(
  UnifiedToolRegistry::Tool.new(
    name: "help_search",
    description: "Search Monadic Chat help documentation",
    parameters: {
      query: {
        type: "string",
        description: "Search query",
        required: true
      },
      num_results: {
        type: "integer",
        description: "Number of results to return",
        default: 3
      }
    }
  ) do |args|
    DirectToolImplementations.search_help(
      args["query"],
      num_results: args["num_results"] || 3
    )
  end
)

# This approach provides:
# 1. Direct HTTP access for simple clients
# 2. MCP compatibility for AI assistants
# 3. Shared implementation to avoid duplication
# 4. Auto-generated API documentation
# 5. Consistent error handling