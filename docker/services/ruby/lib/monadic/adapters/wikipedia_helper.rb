require 'net/http'
require 'uri'
require_relative '../utils/ssl_configuration'

Monadic::Utils::SSLConfiguration.configure! if defined?(Monadic::Utils::SSLConfiguration)

module WikipediaHelper
  def search_wikipedia(search_query: "", language_code: "en")
    number_of_results = 10

    base_url = "https://api.wikimedia.org/core/v1/wikipedia/"
    endpoint = "/search/page"
    url = base_url + language_code + endpoint
    parameters = { "q": search_query, "limit": number_of_results }

    search_uri = URI(url)
    search_uri.query = URI.encode_www_form(parameters)

    begin
      search_response = perform_request_with_retries(search_uri)
    rescue StandardError
      return "Error: The search request could not be completed. The URL is: #{search_uri}"
    end

    begin
      search_data = JSON.parse(search_response)
    rescue JSON::ParserError
      return "Error: The search response could not be parsed. The response is: #{search_response}"
    end

    <<~TEXT
      ```json
      #{search_data.to_json}
      ```
    TEXT
  end

  def perform_request_with_retries(uri)
    retries = 2
    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5) do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request)
      end
      response.body
    rescue Net::OpenTimeout
      if retries.positive?
        retries -= 1
        retry
      else
        return "Error: The request timed out."
      end
    end
  end
end
