# frozen_string_literal: true

require_relative "../../../apps/mermaid_grapher/mermaid_grapher"

module Monadic
  module MCP
    module Adapters
      class MermaidAdapter
        def initialize
          @app = MermaidGrapher.new
        end

        def list_tools
          [
            {
              name: "mermaid_validate_syntax",
              description: "Validate Mermaid diagram syntax and get error messages",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid diagram code to validate"
                  }
                },
                required: ["code"]
              }
            },
            {
              name: "mermaid_preview",
              description: "Generate a preview image of a Mermaid diagram",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid diagram code"
                  },
                  theme: {
                    type: "string",
                    enum: ["default", "dark", "forest", "neutral"],
                    description: "Mermaid theme (default: default)"
                  }
                },
                required: ["code"]
              }
            },
            {
              name: "mermaid_analyze_error",
              description: "Analyze Mermaid syntax errors and get suggestions",
              inputSchema: {
                type: "object",
                properties: {
                  code: {
                    type: "string",
                    description: "Mermaid code with errors"
                  },
                  error: {
                    type: "string",
                    description: "Error message from validation"
                  }
                },
                required: ["code", "error"]
              }
            }
          ]
        end

        def handles_tool?(tool_name)
          tool_name.start_with?("mermaid_")
        end

        def execute_tool(tool_name, arguments)
          case tool_name
          when "mermaid_validate_syntax"
            validate_syntax(arguments["code"])
          when "mermaid_preview"
            preview_diagram(arguments["code"], arguments["theme"])
          when "mermaid_analyze_error"
            analyze_error(arguments["code"], arguments["error"])
          else
            { error: "Unknown tool: #{tool_name}" }
          end
        rescue => e
          puts "Mermaid adapter error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] == "true"
          { error: "Error executing tool: #{e.message}" }
        end

        private

        def validate_syntax(code)
          return { error: "Code is required" } if code.nil? || code.strip.empty?
          return { error: "Code too long (max 5000 characters)" } if code.length > 5000

          result = @app.validate_mermaid_syntax(code: code)
          
          {
            content: [
              {
                type: "text",
                text: result[:valid] ? "✅ Valid Mermaid syntax" : "❌ Invalid syntax: #{result[:error]}"
              }
            ]
          }
        end

        def preview_diagram(code, theme = nil)
          return { error: "Code is required" } if code.nil? || code.strip.empty?
          
          result = @app.preview_mermaid(code: code, theme: theme)
          
          if result[:success]
            {
              content: [
                {
                  type: "text",
                  text: "📊 Mermaid diagram generated successfully!\nSaved as: #{result[:filename]}\nView at: /data/#{result[:filename]}"
                }
              ]
            }
          else
            {
              content: [
                {
                  type: "text",
                  text: "❌ Failed to generate diagram: #{result[:error]}"
                }
              ]
            }
          end
        end

        def analyze_error(code, error)
          result = @app.analyze_mermaid_error(code: code, error: error)
          
          {
            content: [
              {
                type: "text",
                text: result[:analysis]
              }
            ]
          }
        end
      end
    end
  end
end