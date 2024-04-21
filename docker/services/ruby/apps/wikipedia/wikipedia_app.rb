# frozen_string_literal: true

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
      "model": "gpt-4-turbo",
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
end
