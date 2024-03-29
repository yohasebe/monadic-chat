# frozen_string_literal: false

require_relative "./../../lib/helpers/flask_app_client"

class Wikipedia < MonadicApp
  def icon
    "<i class='fab fa-wikipedia-w'></i>"
  end

  def description
    "This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them."
  end

  def initial_prompt
    text = <<~TEXT
You are a consultant who responds to any questions asked by the user. The current date is {{DATE}}.

To answer questions  run `search_wikipedia(search_query, language_code)` function and read the relavant wikipedia aritcle text in the result. Even if you already have the answer, you should still run the function to make sure the answer is based on the most up-to-date information.

Respond to the user in the same language as the user's input. However, do the wikipedia search in English and provide the user with the infrmation translated to the user's language. Only when you are not able to find the information in English, you can make a wikipedia search in the user's language.

Please make sure that when you present a Wikipedia article link to the user, you use the `target="_blank"` attribute in the HTML link tag so that the user can open the link in a new tab. It is okay to provide the user with a link to the English Wikipedia article.

Use the following HTML format in your response:

```
<p>YOUR RESPONSE</p>

<blockquote>
  <a href="URL" target="_blank">URL</a>
</blockquote>
```

    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Wikipedia",
      "model": "gpt-4-0125-preview",
      "temperature": 0.3,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 20,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "initiate_from_assistant": false,
      "tools": [
        { "type": "function",
          "function": {
            "name": "search_wikipedia",
            "description": "A function to search Wikipedia articles, requiring one argument representing the query for the search.",
            "parameters": {
              "type": "object",
              "properties": {
                "search_query": {
                  "type": "string",
                  "description": "query for the search"
                },
                "language_code": {
                  "type": "string",
                  "description": "language code of the Wikipedia to be searched"
                }
              },
              "required": ["search_query", "language_code"]
            }
          }
        }
      ]
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
      ```json
      #{search_data.to_json}
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

  def cosine_similarity(a, b)
    raise ArgumentError, "a and b must be of the same size" if a.size != b.size
    dot_product = a.zip(b).map { |x, y| x * y }.sum
    magnitude_a = Math.sqrt(a.map { |x| x**2 }.sum)
    magnitude_b = Math.sqrt(b.map { |x| x**2 }.sum)
    dot_product / (magnitude_a * magnitude_b)
  end

  def most_similar_text_index(topic, texts)
    embeddings = get_embeddings(topic)
    texts_embeddings = texts.map { |t| get_embeddings(t) }.compact
    cosine_similarities = texts_embeddings.map { |e| cosine_similarity(embeddings, e) }
    cosine_similarities.each_with_index.max[1]
  end

  def split_text(text)
    begin
      tokenized = MonadicApp::TOKENIZER.get_tokens_sequence(text)
      segments = []
      while tokenized.size < MAX_TOKENS_WIKI.to_i
        segment = tokenized[0..MAX_TOKENS_WIKI.to_i]
        segments << MonadicApp::TOKENIZER.decode_tokens(segment)
        tokenized = tokenized[MAX_TOKENS_WIKI.to_i..-1]
      end
      segments << self.flask_app_client.decode_tokens(tokenized)
      segments
    rescue StandardError => e
      return [text]
    end
  end

  def get_embeddings(text, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key = ENV["OPENAI_API_KEY"]

    request["Authorization"] = "Bearer #{api_key}"
    request.body = {
      model: "text-embedding-3-small",
      input: text
    }.to_json

    response = nil
    retries.times do |i|
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      break if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "Error: #{e.message}. Retrying in #{i + 1} seconds..."
      sleep(i + 1)
    end

    begin
      JSON.parse(response.body)["data"][0]["embedding"]
    rescue StandardError => e
      return nil
    end
  end
end
