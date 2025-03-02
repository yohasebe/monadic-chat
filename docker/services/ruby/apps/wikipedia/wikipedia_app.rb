class Wikipedia < MonadicApp
  include OpenAIHelper
  include WikipediaHelper

  icon = "<i class='fab fa-wikipedia-w'></i>"

  description = <<~TEXT
    This is essentially the same as Chat, but for questions that GPT cannot answer, such as questions about events that occurred after the language model cutoff time, it searches Wikipedia to answer them. <a href="https://yohasebe.github.io/monadic-chat/#/basic-apps?id=wikipedia" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are a consultant who responds to any questions asked by the user.

    To answer questions, run the `search_wikipedia(search_query, language_code)` function and read the relevant Wikipedia article text in the result. Even if you already have the answer, you should still run the function to ensure it is based on the most up-to-date information.

    Respond to the user in the same language as the user's input. However, do the Wikipedia search in English and provide the user with information translated into the user's language. Only when you are not able to find the information in English make a Wikipedia search in the user's language.

    Please make sure that when you present a Wikipedia article link to the user, you use the `target="_blank"` attribute in the HTML link tag so that the user can open the link in a new tab. It is okay to provide the user with a link to the English Wikipedia article.

    If the user needs more information or has further questions, you should be able to provide additional details or examples to help the user understand the topic better. You can also provide analogies or explanations in a beginner-friendly manner. You can access URL's content using the `fetch_web_content` function, which takes the URL as a parameter and saves the content in a file. You can then read the content from the file and use it to answer the user's questions. Use this function to fetch the information from the URL mentioned in the Wikipedia article, for instance. Before you actually run the function, make sure that you have the user's consent to access the URL.

    If you cannot find the information on Wikipedia, please inform the user that you cannot find the information and ask them to provide a different question or topic.

    Use the following HTML format in your response:

    ```
    <p>YOUR RESPONSE</p>

    <blockquote>
      <a href="URL" target="_blank">Wikipedia URL</a>
    </blockquote>
    ```
  TEXT

  @settings = {
    group: "OpenAI",
    app_name: "Wikipedia",
    disabled: !CONFIG["OPENAI_API_KEY"],
    models: OpenAIHelper.list_models,
    model: "gpt-4o",
    temperature: 0.3,
    initial_prompt: initial_prompt,
    description: description,
    icon: icon,
    easy_submit: false,
    auto_speech: false,
    initiate_from_assistant: false,
    image: true,
    tools: [
      {
        type: "function",
        function: {
          name: "search_wikipedia",
          description: "A function to search Wikipedia articles, requiring one argument representing the query for the search.",
          parameters: {
            type: "object",
            properties: {
              search_query: {
                type: "string",
                description: "query for the search"
              },
              language_code: {
                type: "string",
                description: "language code of the Wikipedia to be searched"
              }
            },
            required: ["search_query", "language_code"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "fetch_web_content",
          description: "Fetch the content of the web page of the given URL and save it to a file.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "URL of the web page."
              }
            },
            required: ["url"],
            additionalProperties: false
          }
        },
        strict: true
      },
    ]
  }
end
