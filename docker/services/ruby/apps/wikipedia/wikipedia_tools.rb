require "net/http"
require "uri"
require_relative "../../lib/monadic/adapters/wikipedia_helper"

class WikipediaOpenAI < MonadicApp
  include OpenAIHelper
  include WikipediaHelper
  
  def fetch_web_content(url:)
    begin
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Monadic Chat Wikipedia App"
        http.request(request)
      end
      
      if response.code == "200"
        # Save content to a file
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        filename = "web_content_#{timestamp}.txt"
        # Use appropriate path based on environment
        filepath = if defined?(Monadic::Utils::Environment) && Monadic::Utils::Environment.in_container?
                     File.join(SHARED_VOL, filename)
                   else
                     File.join(LOCAL_SHARED_VOL, filename)
                   end
        
        File.write(filepath, response.body)
        
        "Content saved to file: #{filename}"
      else
        "Error: Failed to fetch content. HTTP status: #{response.code}"
      end
    rescue StandardError => e
      "Error: #{e.message}"
    end
  end
end