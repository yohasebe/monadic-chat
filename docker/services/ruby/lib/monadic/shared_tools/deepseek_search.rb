# frozen_string_literal: true

require 'json'
require 'uri'
require_relative '../utils/http_client'
require_relative '../utils/error_formatter'
require_relative '../utils/extra_logger'

module Monadic
  module SharedTools
    # Web search for DeepSeek chats through DeepSeek's own Search and Fetch
    # APIs, with the chat's DeepSeek key.
    #
    # Source of truth for:
    #   - The function schemas (deepseek_search / deepseek_fetch) that the
    #     DeepSeek helper offers when the message may search the web.
    #   - The system-prompt fragment that tells the model when to use them.
    #   - The requests to the two APIs and the results given to the model,
    #     for the chat's tools and for the subtasks of parallel dispatch.
    #
    # Each request is billed, so one is made only when a tool is called (or
    # a subtask asked to search runs); none is retried.
    module DeepSeekSearch
      SEARCH_ENDPOINT = "https://api.deepseek.com/v1/tools/search"
      FETCH_ENDPOINT = "https://api.deepseek.com/v1/tools/fetch"

      MAX_QUERY_LENGTH = 128
      MAX_COUNT = 50
      DEFAULT_COUNT = 5
      MAX_URL_LENGTH = 8192

      TIMEOUTS = { connect: 10, read: 60, write: 30 }.freeze

      TOOL_NAMES = %w[deepseek_search deepseek_fetch].freeze

      TOOLS = [
        {
          type: "function",
          function: {
            name: "deepseek_search",
            description: "search the web for the given query and return the results: the title, url, summary and date of each page.",
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "query to search for (at most 128 characters). Operators such as site:example.com, after:2025-01-01 and lang:en narrow the search."
                },
                count: {
                  type: "integer",
                  description: "number of results to return (default: 5, at most 50)."
                }
              },
              required: ["query"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "deepseek_fetch",
            description: "fetch the web page of the given url and return its content as markdown.",
            parameters: {
              type: "object",
              properties: {
                url: {
                  type: "string",
                  description: "url of the web page (http or https)."
                }
              },
              required: ["url"]
            }
          }
        }
      ].freeze

      PROMPT = <<~TEXT

        Web search is available through deepseek_search (search the web) and deepseek_fetch (read a page). Use them when the user asks you to, or when the answer needs current information or a fact you should check; not for what you can answer as it is, or when the user asks you not to. Always respond to the user in the language they used. When you use what you found, cite the sources as HTML links: <a href="URL" target="_blank" rel="noopener noreferrer">Title</a>.
      TEXT

      module_function

      # The results of a search, for the model: { "query", "results" =>
      # [{ "title", "url", "summary", "date" }], "websearch_agent" }, or
      # { "error" => ... }.
      def search(query:, count: DEFAULT_COUNT, api_key:)
        query = query.to_s.strip
        return { "error" => "DeepSeek search error: the query is empty." } if query.empty?
        if query.length > MAX_QUERY_LENGTH
          return { "error" => "DeepSeek search error: the query must be #{MAX_QUERY_LENGTH} characters or fewer." }
        end

        count = count.to_i
        count = DEFAULT_COUNT unless count.positive?
        body = { "query" => query, "count" => [count, MAX_COUNT].min }
        parsed = post(SEARCH_ENDPOINT, body, api_key, "search")
        return parsed if parsed.key?("error")

        results = Array(parsed["results"]).select { |r| r.is_a?(Hash) }.map do |r|
          { "title" => r["title"], "url" => r["url"],
            "summary" => r["summary"].to_s.empty? ? r["snippet"] : r["summary"],
            "date" => r["date"] }.compact
        end
        { "query" => query, "results" => results, "websearch_agent" => "deepseek" }
      end

      # The content of a page, for the model: { "title", "url", "content",
      # "websearch_agent" }, or { "error" => ... }.
      def fetch(url:, api_key:)
        url = url.to_s.strip
        problem = url_problem(url)
        return { "error" => "DeepSeek fetch error: #{problem}" } if problem

        parsed = post(FETCH_ENDPOINT, { "url" => url }, api_key, "fetch")
        return parsed if parsed.key?("error")

        { "title" => parsed["title"], "url" => url, "content" => parsed["content"].to_s,
          "websearch_agent" => "deepseek" }.compact
      end

      def url_problem(url)
        return "the url is empty." if url.empty?
        return "the url must be #{MAX_URL_LENGTH} characters or fewer." if url.length > MAX_URL_LENGTH

        uri = URI.parse(url)
        return "only http and https urls can be fetched." unless uri.is_a?(URI::HTTP) && uri.host.to_s != ""
        return "the url must not carry a user name or password." if uri.userinfo

        nil
      rescue URI::InvalidURIError
        "the url is not valid."
      end

      # The parsed body of a successful request, or { "error" => ... } with
      # the API's message (the key taken out of it).
      def post(endpoint, body, api_key, label)
        api_key = api_key.to_s.strip
        return { "error" => "DeepSeek #{label} error: DEEPSEEK_API_KEY is not set." } if api_key.empty?

        headers = { "Content-Type" => "application/json", "Authorization" => "Bearer #{api_key}" }
        res = Monadic::Utils::HttpClient.rest(**TIMEOUTS).headers(headers).post(endpoint, json: body)
        text = res.body.to_s
        parsed = (JSON.parse(text) rescue nil)
        unless res.status.success? && parsed.is_a?(Hash)
          Monadic::Utils::ExtraLogger.log { "[DeepSeek] #{label} API error: HTTP #{res.status.to_i}" }
          return { "error" => "DeepSeek #{label} error: #{error_text(parsed, res.status.to_i, api_key)}" }
        end

        parsed
      rescue HTTP::Error => e
        { "error" => "DeepSeek #{label} error: #{clean(e.message, api_key)}" }
      end

      def error_text(parsed, status, api_key)
        error = parsed.is_a?(Hash) ? parsed["error"] : nil
        message = error.is_a?(Hash) ? error["message"] : error
        message = "HTTP #{status}" if message.to_s.strip.empty?
        message = "#{message} (HTTP #{status})" unless message.include?(status.to_s)
        clean(message, api_key)
      end

      def clean(text, api_key)
        text = text.to_s
        text = text.gsub(api_key, "[REDACTED]") unless api_key.to_s.empty?
        Monadic::Utils::ErrorFormatter.scrub_identifiers(text)
      end
    end
  end
end
