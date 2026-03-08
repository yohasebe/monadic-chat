# frozen_string_literal: true

require 'json'

module InteractionUtils
  def tavily_fetch(url:)
    api_key = CONFIG["TAVILY_API_KEY"]

    # Check if API key is present
    if api_key.nil? || api_key.empty?
      return "ERROR: Tavily API key is not configured"
    end

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }

    body = {
      "urls" => [url]  # Must be an array according to API docs
    }

    target_uri = "https://api.tavily.com/extract"

    begin
      http = HTTP.headers(headers)
      res = http.timeout(connect: OPEN_TIMEOUT, write: WRITE_TIMEOUT, read: READ_TIMEOUT).post(target_uri, json: body)

      if res.status.success?
        res_json = JSON.parse(res.body)

        # Check for failed results
        if res_json["failed_results"] && !res_json["failed_results"].empty?
          failed = res_json["failed_results"][0]
          return { error: "Tavily fetch failed: #{failed['error']} for URL: #{failed['url']}" }
        end

        # Extract content from results array
        if res_json["results"] && res_json["results"].is_a?(Array) && !res_json["results"].empty?
          result = res_json["results"][0]

          # Try different possible content fields
          content = result["raw_content"] || result["content"] || result["text"]

          if content.nil? || content.empty?
            return { error: "No content found in Tavily response" }
          end

          return content
        else
          return { error: "No results found in Tavily response" }
        end
      else
        # Parse the response body only once
        error_report = begin
          JSON.parse(res.body)
        rescue StandardError
          res.body.to_s
        end
        error_message = error_report.is_a?(Hash) ? (error_report["error"] || error_report["message"] || "Unknown error") : error_report.to_s
        { error: "Tavily API error: #{error_message}" }
      end
    rescue HTTP::Error, HTTP::TimeoutError => e
      { error: "Network error occurred: #{e.message}" }
    rescue JSON::ParserError => e
      { error: "Error parsing response: #{e.message}" }
    rescue StandardError => e
      STDERR.puts "[ERROR] Unexpected error in tavily_fetch: #{e.class} - #{e.message}"
      STDERR.puts e.backtrace.first(5).join("\n")
      { error: "Unexpected error in tavily_fetch: #{e.message}" }
    end
  end
end
