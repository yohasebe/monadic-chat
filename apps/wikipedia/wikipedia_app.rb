# frozen_string_literal: false

class Wikipedia < MonadicApp
  MAX_TOKENS_WIKI = ENV["MAX_TOKENS_WIKI"] || 1024

  def icon
    "<i class='fab fa-wikipedia-w'></i>"
  end

  def description
    "This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. If the query is in a non-English language, the Wikipedia search is performed in English, and the results are translated into the original language."
  end

  def initial_prompt
    text = <<~TEXT
      You are a consultant who responds to any questions asked by the user. The current date is {{DATE}}. To answer questions that refer to events after the data cutoff time in September 2021, please run a Wikipedia search function To do a Wikipedia search, run `search_wikipedia(query)` and read "SNIPPETS" in the result. When responding based on the Wikipedia search, make sure to refer to the source article in "SOURCE".

      If the search results do not contain enough information, please let the user know. Even if the user's question is in a language other than English, please make a Wikipedia query in English and then answer in the user's language.
    TEXT
    text.strip
  end

  def settings
    {
      "app_name": "Wikipedia",
      "model": "gpt-3.5-turbo-0613",
      "temperature": 0.3,
      "top_p": 0.0,
      "max_tokens": 1000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "description": description,
      "icon": icon,
      "easy_submit": false,
      "auto_speech": false,
      "functions": [{
        "name" => "search_wikipedia",
        "description" => "A function to search Wikipedia articles, requiring one argument representing the query to be searched.",
        "parameters": {
          "type": "object",
          "properties": {
            "keywords": {
              "type": "string",
              "description": "Wikipedia search keywords"
            }
          },
          "required": ["keywords"]
        }
      }]
    }
  end

  def search_wikipedia(keywords, num_retrials: 10)
    base_url = "https://en.wikipedia.org/w/api.php"

    search_params = {
      action: "query",
      list: "search",
      format: "json",
      srsearch: keywords,
      utf8: 1,
      formatversion: 2,
      "speech_lang": "en-US",
      "speech_rate": 1.0
    }

    search_uri = URI(base_url)
    search_uri.query = URI.encode_www_form(search_params)
    search_response = Net::HTTP.get(search_uri)
    search_data = JSON.parse(search_response)

    raise if search_data["query"]["search"].empty?

    title = search_data["query"]["search"][0]["title"]

    content_params = {
      action: "query",
      prop: "extracts",
      format: "json",
      titles: title,
      explaintext: 1,
      utf8: 1,
      formatversion: 2,
      "pdf": false
    }

    content_uri = URI(base_url)
    content_uri.query = URI.encode_www_form(content_params)
    content_response = Net::HTTP.get(content_uri)
    content_data = JSON.parse(content_response)

    result_data = content_data["query"]["pages"][0]["extract"]
    tokenized = TOKENIZER.encode(result_data)
    if tokenized.size > MAX_TOKENS_WIKI.to_i
      ratio = MAX_TOKENS_WIKI.to_f / tokenized.size
      result_data = result_data[0..(result_data.size * ratio).to_i]
    end
    <<~TEXT
      "SEARCH SNIPPETS:
      ```MediaWiki
      #{result_data}
      ```

      "SOURCE": https://en.wikipedia.org/wiki/#{title}
    TEXT
  rescue StandardError
    num_retrials -= 1
    if num_retrials.positive?
      sleep 1
      search_wikipedia(keywords, num_retrials: num_retrials)
    else
      <<~TEXT
        "SEARCH SNIPPETS: ```
        information not found"
        ```
      TEXT
    end
  end
end
