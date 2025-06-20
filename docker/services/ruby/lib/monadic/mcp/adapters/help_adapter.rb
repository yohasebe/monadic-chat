# frozen_string_literal: true

require_relative '../../utils/help_embeddings'
require_relative '../../utils/debug_helper'

module Monadic
  module MCP
    module Adapters
      class HelpAdapter
        include DebugHelper

        def initialize
          @help_embeddings = HelpEmbeddings.new
        end

        def list_tools
          [
            {
              name: "monadic_help_search",
              description: "Search Monadic Chat documentation and help content",
              inputSchema: {
                type: "object",
                properties: {
                  query: {
                    type: "string",
                    description: "Search query for finding relevant help content"
                  }
                },
                required: ["query"]
              }
            },
            {
              name: "monadic_help_get_categories",
              description: "Get all available help categories",
              inputSchema: {
                type: "object",
                properties: {}
              }
            },
            {
              name: "monadic_help_get_by_category",
              description: "Get help items from a specific category",
              inputSchema: {
                type: "object",
                properties: {
                  category: {
                    type: "string",
                    description: "Category name to retrieve items from"
                  }
                },
                required: ["category"]
              }
            }
          ]
        end

        def handles_tool?(tool_name)
          tool_name.start_with?("monadic_help_")
        end

        def execute_tool(tool_name, arguments)
          case tool_name
          when "monadic_help_search"
            search_help(arguments["query"])
          when "monadic_help_get_categories"
            get_categories
          when "monadic_help_get_by_category"
            get_by_category(arguments["category"])
          else
            { error: "Unknown tool: #{tool_name}" }
          end
        rescue => e
          puts "Help adapter error: #{e.message}" if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] == "true"
          puts e.backtrace.join("\n") if defined?(CONFIG) && CONFIG["EXTRA_LOGGING"] == "true"
          { error: "Error executing tool: #{e.message}" }
        end

        private

        def search_help(query)
          return { error: "Query is required" } if query.nil? || query.strip.empty?
          return { error: "Query too long (max 200 characters)" } if query.length > 200
          
          # Sanitize query - allow only alphanumeric, spaces, and common punctuation
          unless query.match?(/\A[\p{L}\p{N}\s\-_.,!?'"]+\z/u)
            return { error: "Query contains invalid characters" }
          end

          # Search for relevant help content
          results = @help_embeddings.search(
            query: query,
            num_results: CONFIG["HELP_CHUNKS_PER_RESULT"]&.to_i || 3
          )

          if results.empty?
            return {
              content: "No relevant help content found for your query.",
              results: []
            }
          end

          # Format results
          formatted_results = results.map do |result|
            {
              title: result[:title],
              content: result[:content],
              category: result[:metadata]&.dig("category"),
              relevance_score: result[:distance]
            }
          end

          {
            content: [
              {
                type: "text",
                text: format_search_results(formatted_results, query)
              }
            ]
          }
        end

        def get_categories
          categories = @help_embeddings.get_unique_categories
          
          {
            content: [
              {
                type: "text",
                text: "Found #{categories.length} categories:\n\n" + categories.join("\n")
              }
            ]
          }
        end

        def get_by_category(category)
          return { error: "Category is required" } if category.nil? || category.strip.empty?
          return { error: "Category name too long (max 100 characters)" } if category.length > 100
          
          # Sanitize category - allow only alphanumeric, spaces, and hyphens
          unless category.match?(/\A[\w\s\-]+\z/)
            return { error: "Category contains invalid characters" }
          end

          items = @help_embeddings.get_by_category(category)
          
          if items.empty?
            return {
              content: [
                {
                  type: "text",
                  text: "No items found in category: #{category}"
                }
              ]
            }
          end

          {
            content: [
              {
                type: "text",
                text: format_category_results(category, items)
              }
            ]
          }
        end

        def format_search_results(results, query)
          output = ["# Search Results for \"#{query}\"\n"]
          
          results.each_with_index do |result, index|
            output << "## #{index + 1}. #{result[:title]}"
            output << "**Category**: #{result[:category] || 'General'}"
            output << "**Relevance**: #{(1 - result[:relevance_score]).round(3)}"
            output << ""
            output << result[:content]
            output << "\n---\n"
          end

          output.join("\n")
        end
        
        def format_category_results(category, items)
          output = ["# Items in category: #{category}\n"]
          
          items.each_with_index do |item, index|
            output << "## #{index + 1}. #{item[:title]}"
            output << ""
            output << item[:content]
            output << "\n---\n"
          end
          
          output.join("\n")
        end
      end
    end
  end
end