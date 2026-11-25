# frozen_string_literal: false

# The route that turns a web page into text for the message

# Fetch the webpage content
post "/fetch_webpage" do
  content_type :json

  return error_json("No URL provided") unless params["pageURL"]

  begin
    url = params["pageURL"]
    url_decoded = CGI.unescape(url)
    label = params["urlLabel"].to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    # Web UI always uses Selenium for URL fetching (Tavily is only
    # exposed inside Research Assistant apps).
    markdown = MonadicApp.fetch_webpage(url)

    if markdown.to_s.strip.empty?
      return error_json("No content could be extracted from the webpage")
    end

    webpage_text = "URL: " + url_decoded + "\n---\n" + markdown
    result = if label.to_s != ""
              "---\n" + label + "\n---\n" + webpage_text
            else
              "---\n" + webpage_text
            end

    { success: true, content: result }.to_json
  rescue => e
    error_json("Error fetching webpage: #{e.message}")
  end
end
