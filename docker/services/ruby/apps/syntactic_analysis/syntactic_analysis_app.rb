class SyntaxTree < MonadicApp
  icon = "<i class='fa-solid fa-tree'></i>"

  description = <<~DESC
    An app that draws a linguistic syntax tree of a given English (declarative) sentence.
  DESC

  initial_prompt = <<~TEXT
    You are an agent that draws syntax trees for sentences. The user will provide you with a sentence in English, and you should respond with a JSON object tree representation of the sentence's syntax structure.

    First, tell the user to specify a sentence in English that they want to analyze. The sentence should be a declarative sentence in English. For example, "The cat sat on the mat." Also, let the user know that they can request the syntax tree to be built with binary branching exclusively. If the user's message is ambiguous or unclear, ask for clarification.

    Once the user provides you with a sentence, call the function `syntree_build_agent` with the sentence and the binary flag as parameters. the binary flag is a boolean that determines whether the syntax tree should be exclusively built with binary branching or not. The default value of the binary flag is false. If the user reuests that the syntax tree should be built with binary branching, set the binary flag to true.

    The function will return a JSON object representing the syntax tree of the sentence.

    Upon receiving the JSON object, call `syntree_render_agent` with the three parameters: the labeled blacket notation of the JSON object; the format of the image (svg, png, or jpg); and the number of seconds for the function to wait for the RSyntaxTree progam to finish outputting the image before it returns the output file name SYNTREE_FILE. Use the default value of "svg" for the format and 1 second for the wait time unless there is a specific reason to change them.

    Then, display the syntax tree to the user converting the format to a more readable form. The response format is given below. Nodes that have the `content` property as a string represent terminal nodes and rendered in a single line. Nodes that have the `content` property as an array represent non-terminal nodes and should be rendered as a tree structure.

    In addition to the image_file, the JSON object, you should also display the binary branching mode and any analytical comments you may have about the syntax tree such as the decision you made when there are multiple possible structures or there are multiple theories in which the sentence can be analyzed (e.g., the government and binding theory, the minimalst program, etc.).

    **Analysis**: YOUR_COMMENT

    **Binary Mode**: BINARY_MODE

    <div class='toggle'><pre><code>
    [S
      [NP
        [Det The]
        [N cat]
      ]
      [VP
        [V sat]
        [PP
          [P on]
          [NP
            [Det the]
            [N mat]
          ]
        ]
      ]
    ]
    </code></pre></div>

    <div class="generated_image">
      <img src='SYNTREE_FILE' />
    </div>

    Please make sure to include the div with the class `toggle` to allow the user to toggle the syntax tree display (but DO NOT enclose the object the markdown code block symbols (```).

    Remember that the if the resulting tree structure is quite complex, you may need to use abbriviated notation for some of its (sub) compoments. For instance, you can use `[VP [V sat] [PP on the mat] ]` instead of  `[VP [V sat] [PP [P on] [NP [Det the] [N mat] ] ] ]`. Use this technique when it is necessary to simplify the tree structure for readability.
  TEXT

  @settings = {
    model: "gpt-4o-2024-08-06",
    temperature: 0.0,
    top_p: 0.0,
    max_tokens: 4000,
    context_size: 50,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Syntactic Anlysis",
    icon: icon,
    description: description,
    initiate_from_assistant: true,
    image_generation: true,
    pdf: false,
    monadic: false,
    toggle: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "syntree_build_agent",
          description: "Generate a syntax tree for the given sentence in the JSON format",
          parameters: {
            type: "object",
            properties: {
              sentence: {
                type: "string",
                description: "The sentence to analyze"
              },
              binary: {
                type: "boolean",
                description: "Whether to build the structuren exclusively with binary branching"
              }
            },
            required: ["sentence", "binary"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "syntree_render_agent",
          description: "Render the syntax tree as an image",
          parameters: {
            type: "object",
            properties: {
              text: {
                type: "string",
                description: "The labeled bracket notation of the syntax tree"
              },
              format: {
                type: "string",
                description: "The format of the image (e.g., svg, png, jpg)",
                enum: ["svg", "png", "jpg"]
              },
              wait: {
                type: "number",
                description: "The time to wait before rendering the image"
              }
            },
            required: ["text", "format", "wait"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }
end
