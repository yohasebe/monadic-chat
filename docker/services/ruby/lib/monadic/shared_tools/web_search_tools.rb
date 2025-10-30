# frozen_string_literal: true

require 'net/http'
require 'uri'

# Unified Web Search Tools for Monadic Chat
# Consolidates web search and content fetching capabilities
#
# This module provides:
# - Provider-aware web search (native or Tavily)
# - URL content fetching with HTTP/HTTPS
# - Tavily API integration for providers without native search
#
# Usage in MDSL:
#   tools do
#     import_shared_tools :web_search_tools, visibility: "conditional"
#   end
#
# Available tools:
#   - search_web: Search the web using provider-native or Tavily API
#   - fetch_web_content: Fetch and save content from a URL
#   - tavily_search: Direct Tavily API search (conditional - requires API key)
#   - tavily_fetch: Fetch content via Tavily API (conditional - requires API key)

module MonadicSharedTools
  module WebSearchTools
    include MonadicHelper

    # Check if web search tools are available
    # Returns true if either:
    # 1. Provider has native web search (OpenAI, Claude, Gemini, Grok, Perplexity)
    # 2. Tavily API key is configured
    def self.available?
      # Check for Tavily API key
      has_tavily = CONFIG && !CONFIG["TAVILY_API_KEY"].to_s.strip.empty?

      # Native search providers are always available (provider-side check)
      # This check is primarily for Tavily availability
      has_tavily
    end

    # Search the web using provider-appropriate search method
    #
    # Automatically routes to the best search backend based on AI provider:
    # - OpenAI: Native web search
    # - Claude: Native web search
    # - Gemini: URL Context feature
    # - Grok: Grok Live Search
    # - Perplexity: Native search (always enabled)
    # - Mistral/Cohere/DeepSeek: Tavily API (requires TAVILY_API_KEY)
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

      # Provider detection and routing
      provider = self.class.name.downcase

      # For providers with native websearch support
      if provider.include?("openai")
        return "Web search results are being processed by the AI model's native capabilities. Please continue with your response based on the search query: #{query}"
      elsif provider.include?("claude")
        return "Web search is handled through Claude's native search capabilities. Processing query: #{query}"
      elsif provider.include?("gemini")
        return "Web search is handled through Gemini's native URL Context feature. Processing query: #{query}"
      elsif provider.include?("grok")
        return "Web search is handled through Grok's native Live Search. Processing query: #{query}"
      elsif provider.include?("perplexity")
        return "Web search is handled through Perplexity's native search. Processing query: #{query}"
      end

      # For providers that use Tavily (Mistral, Cohere, DeepSeek, Ollama)
      if CONFIG["TAVILY_API_KEY"] && respond_to?(:tavily_search)
        return tavily_search(query: query, n: max_results)
      else
        error_msg = if !CONFIG["TAVILY_API_KEY"]
          "Web search is not available. Please ensure TAVILY_API_KEY is configured."
        else
          "Web search is not available for this provider. This app does not include Tavily support."
        end
        return { success: false, error: error_msg }
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

    # Search the web using Tavily API
    #
    # Performs a web search using the Tavily API, which provides search results
    # optimized for AI applications. Requires TAVILY_API_KEY to be configured.
    #
    # Note: This method delegates to TavilyHelper.tavily_search if available.
    # It is exposed as a tool for providers without native search capabilities.
    #
    # @param query [String] The search query
    # @param n [Integer] Number of results to return (default: 3, max: 10)
    # @return [Hash] Search results with URLs, titles, and content snippets
    #
    # @example Basic search
    #   tavily_search(query: "latest AI news", n: 5)
    #
    # @example Research query
    #   tavily_search(query: "quantum computing breakthroughs 2025", n: 10)
    def tavily_search(query:, n: 3)
      # Validate query
      if query.to_s.strip.empty?
        return { error: "Query cannot be empty" }
      end

      # Delegate to TavilyHelper if available
      if respond_to?(:super_method_missing, true) || defined?(TavilyHelper)
        begin
          # Call the TavilyHelper implementation via super or direct call
          super(query: query, n: n)
        rescue NoMethodError
          { error: "Tavily search is not available. Please include TavilyHelper in your app." }
        end
      else
        { error: "Tavily search is not available. Please include TavilyHelper in your app." }
      end
    end

    # Fetch content from a URL using Tavily API
    #
    # Extracts and returns the full content of a webpage using Tavily's extract API.
    # Useful for getting detailed content from URLs found in search results.
    #
    # Note: This method delegates to the tavily_fetch implementation in
    # interaction_utils.rb if available.
    #
    # @param url [String] The URL to fetch content from
    # @return [Hash, String] Extracted content or error message
    #
    # @example Fetch article content
    #   tavily_fetch(url: "https://example.com/article")
    def tavily_fetch(url:)
      # Validate URL
      if url.to_s.strip.empty?
        return { error: "URL cannot be empty" }
      end

      # Delegate to the tavily_fetch implementation
      if respond_to?(:super_method_missing, true) || method_defined?(:tavily_fetch)
        begin
          super(url: url)
        rescue NoMethodError
          { error: "Tavily fetch is not available. Please include TavilyHelper in your app." }
        end
      else
        { error: "Tavily fetch is not available. Please include TavilyHelper in your app." }
      end
    end
  end
end
