# frozen_string_literal: false

class Wikipedia < MonadicApp
  MAX_TOKENS_WIKI = ENV["MAX_TOKENS_WIKI"] || 1024

  def icon
    "<i class='fab fa-wikipedia-w'></i>"
  end

  def description
    "This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them."
  end

  def initial_prompt
    text = <<~TEXT
      You are a consultant who responds to any questions asked by the user. The current date is {{DATE}}. To answer questions that refer to events after the data cutoff time, please run a Wikipedia search function To do a Wikipedia search, run `search_wikipedia(search_query, language_code)` and read "SNIPPETS" in the result. In your response to the user based on the Wikipedia search, make sure to refer to the source article in the following HTML format:

      ```
      <p>YOUR RESPONSE</p>

      <blockquote>
        <a href="URL" target="_blank" rel="noopener noreferrer">URL</a>
      </blockquote>

      ```

      If the user requests for more details about your response, retrieve the contents of the URL of the above wikipedia article by running `read_wikipedia_article(url)`, and then refer to the information therein to respond to the user.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Wikipedia",
      "model": "gpt-3.5-turbo-1106",
      "temperature": 0.3,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 8,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "functions":
        [{
          "name" => "search_wikipedia",
          "description" => "A function to search Wikipedia articles, requiring one argument representing the query to be searched.",
          "parameters": {
            "type": "object",
            "properties": {
              "search_query": {
                "type": "string",
                "description": "Wikipedia search query"
              },
              "language_code": {
                "type": "string",
                "description": "language code of the Wikipedia to be searched"
              }
            },
            "required": ["search_query", "language_code"]
          }
        },
        {
          "name" => "read_wikipedia_article",
          "description" => "A function to get Wikipedia article text, requiring one argument representing the url of the article.",
          "parameters": {
            "type": "object",
            "properties": {
              "url": {
                "type": "string",
                "description": "Wikipedia article url"
              }
            },
            "required": ["url"]
          }
        }]
    }
  end

  def search_wikipedia(hash)
    search_query = hash[:search_query]
    language_code = hash[:language_code] || "en"
    number_of_results = 10

    base_url = 'https://api.wikimedia.org/core/v1/wikipedia/'
    endpoint = '/search/page'
    url = base_url + language_code + endpoint
    parameters = {"q": search_query, "limit": number_of_results}

    search_uri = URI(url)
    search_uri.query = URI.encode_www_form(parameters)

    search_response = perform_request_with_retries(search_uri)
    search_data = JSON.parse(search_response)

    <<~TEXT
      "SNIPPETS:
      ```json
      #{search_data.to_json}
      ```
    TEXT
  end

  def read_wikipedia_article(hash)
    url = hash[:url]
    article_uri = URI(url)

    article_response = perform_request_with_retries(article_uri)

    # parse the response as HTML and retrieve all the text contents of <p> tags in the article
    # and join them with a space
    article_data_text = Nokogiri::HTML(article_response).css('p').map(&:text).join(' ').to_s

    tokenized = TOKENIZER.encode(article_data_text)
    if tokenized.size > MAX_TOKENS_WIKI.to_i
      ratio = MAX_TOKENS_WIKI.to_f / tokenized.size
      article_data_text = article_data_text[0..(article_data_text.size * ratio).to_i]
    end

    <<~TEXT
      "SNIPPETS:
      ```json
      #{article_data_text}
      ```
    TEXT
  end

  def perform_request_with_retries(uri)
    retries = 2
    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5) do |http|
        request = Net::HTTP::Get.new(uri)
        http.request(request)
      end
      response.body
    rescue Net::OpenTimeout
      if retries > 0
        retries -= 1
        retry
      else
        raise
      end
    end
  end
end
