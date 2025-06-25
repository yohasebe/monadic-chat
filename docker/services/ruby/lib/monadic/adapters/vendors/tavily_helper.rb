# frozen_string_literal: true

require_relative "../../utils/debug_helper"

module TavilyHelper
  include DebugHelper
  OPEN_TIMEOUT = 10 # Timeout for opening a connection (seconds)
  READ_TIMEOUT = 60 # Timeout for reading data (seconds)
  WRITE_TIMEOUT = 60 # Timeout for writing data (seconds)

  # Number of retries for API requests
  MAX_RETRIES = 10
  # Delay between retries (seconds)
  RETRY_DELAY = 2

  # NOTE: tavily_fetch is implemented in interaction_utils.rb
  # This is here only for module completeness
  # The actual implementation used by the application is in interaction_utils.rb

  def tavily_search(query:, n: 1)
    DebugHelper.debug("tavily_search called with query: #{query}, n: #{n}", category: :web_search, level: :debug)
    
    api_key = CONFIG["TAVILY_API_KEY"]
    
    # Check if API key is present
    if api_key.nil? || api_key.empty?
      return { error: "Tavily API key is not configured. Please set TAVILY_API_KEY in your environment." }
    end
    
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "query" => query,
      "topic": "general",
      "search_depth": "advanced",
      "max_results": n,
      "time_range": nil,
      # days parameter is only available for "news" topic
      # "days": 3,
      "include_answer": true,
      "include_raw_content": false,
      "include_images": false,
      "include_image_descriptions": false,
      "include_domains": [],
      "exclude_domains": []
    }

    target_uri = "https://api.tavily.com/search"

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      if res.status.success?
        res = JSON.parse(res.body)
        res["websearch_agent"] = "tavily"
      else
        JSON.parse(res.body)
        error_report = JSON.parse(res.body)
        res ="ERROR: #{error_report}"
      end

      res
    rescue HTTP::Error, HTTP::TimeoutError => e
      "Error occurred: #{e.message}"
    end
  end
end
