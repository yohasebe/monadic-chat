# frozen_string_literal: true

require 'net/http'
require 'uri'

# Shared Web Tools for Monadic Chat
# Provides web search and content fetching capabilities
#
# This module provides:
# - Provider-aware web search (native or Tavily)
# - URL content fetching with error handling
# - Automatic file saving to shared folder
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :web_tools, visibility: "always"
#   end
#
# Available tools:
#   - search_web: Search the web using provider-native or Tavily API
#   - fetch_web_content: Fetch and save content from a URL

module MonadicSharedTools
  module WebTools
    include MonadicHelper

    # Search the web using provider-appropriate search method
    #
    # Automatically routes to the best search backend based on AI provider:
    # - OpenAI: Native web search (with Tavily fallback)
    # - Claude: Native web search via WebSearchAgent
    # - Gemini: URL Context feature
    # - Grok: Grok Live Search
    # - Mistral/Cohere/DeepSeek: Tavily API
    #
    # @param query [String] The search query
    # @param max_results [Integer] Maximum number of results to return (default: 5)
    # @return [String, Hash] Search results or status message
    #
    # @example Search for Python documentation
    #   search_web(query: "Python asyncio tutorial", max_results: 5)
    #
    # @example Search recent news
    #   search_web(query: "AI breakthroughs 2025")
    def search_web(query:, max_results: 5)
      # Validate input
      unless query
        return {
          success: false,
          error: "Query parameter is required"
        }
      end

      if query.to_s.strip.empty?
        return {
          success: false,
          error: "Query cannot be empty"
        }
      end

      # Use existing websearch_agent if available (includes provider routing)
      if respond_to?(:websearch_agent)
        websearch_agent(query: query)
      # Fallback to Tavily if available
      elsif respond_to?(:tavily_search) && CONFIG["TAVILY_API_KEY"]
        tavily_search(query: query, n: max_results)
      else
        {
          success: false,
          error: "Web search is not available. Please ensure TAVILY_API_KEY is configured or use a provider with native search support."
        }
      end
    end

    # Fetch web content from a URL and save to shared folder
    #
    # Downloads content from the specified URL using HTTP/HTTPS and saves it
    # to a timestamped file in the shared folder for later access.
    #
    # Features:
    # - HTTP/HTTPS support with SSL
    # - Custom User-Agent header
    # - Automatic file naming with timestamp
    # - Error handling for network issues
    # - Timeout protection (5s open, 10s read)
    #
    # @param url [String] The URL to fetch content from
    # @param timeout [Integer] Request timeout in seconds (default: 10)
    # @return [Hash] Success status, filepath, and metadata
    #
    # @example Fetch Wikipedia article
    #   fetch_web_content(url: "https://en.wikipedia.org/wiki/Ruby_(programming_language)")
    #   # => {success: true, filepath: "web_content_20250129_143025.txt", ...}
    #
    # @example Fetch with custom timeout
    #   fetch_web_content(url: "https://example.com/large-file", timeout: 30)
    def fetch_web_content(url:, timeout: 10)
      # Validate URL
      unless url
        return {
          success: false,
          error: "URL parameter is required"
        }
      end

      # Validate URL format
      begin
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return {
            success: false,
            error: "Invalid URL format. Only HTTP and HTTPS URLs are supported."
          }
        end
      rescue URI::InvalidURIError => e
        return {
          success: false,
          error: "Invalid URL format: #{e.message}"
        }
      end

      # Fetch content
      begin
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: 5,
          read_timeout: timeout
        ) do |http|
          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = 'Monadic Chat Web Tools'
          http.request(request)
        end

        # Check response status
        unless response.code == '200'
          return {
            success: false,
            error: "Failed to fetch content. HTTP status: #{response.code} #{response.message}"
          }
        end

        # Save content to shared folder
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        filename = "web_content_#{timestamp}.txt"

        # Use appropriate path based on environment
        data_dir = if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
                     SHARED_VOL
                   else
                     LOCAL_SHARED_VOL
                   end

        filepath = File.join(data_dir, filename)
        File.write(filepath, response.body, encoding: 'UTF-8')

        {
          success: true,
          filepath: filename,
          full_path: filepath,
          size: response.body.bytesize,
          url: url,
          status_code: response.code,
          content_type: response['Content-Type'],
          message: "Content successfully fetched from #{url} and saved to #{filename}"
        }

      rescue Net::OpenTimeout => e
        {
          success: false,
          error: "Connection timeout: Could not connect to #{uri.host} within #{timeout} seconds"
        }
      rescue Net::ReadTimeout => e
        {
          success: false,
          error: "Read timeout: Could not read from #{uri.host} within #{timeout} seconds"
        }
      rescue StandardError => e
        {
          success: false,
          error: "Failed to fetch content: #{e.message}"
        }
      end
    end
  end
end
