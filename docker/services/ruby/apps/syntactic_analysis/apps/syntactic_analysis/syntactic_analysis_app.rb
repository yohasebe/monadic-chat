class SyntacticAnalysis < MonadicApp
  include OpenAIHelper

  icon = "<i class='fa-solid fa-tree'></i>"

  description = <<~DESC
    An app that draws a linguistic syntax tree of a given English sentence.
  DESC

  initial_prompt = <<~TEXT
    You are an agent that draws syntax trees for sentences. The user will provide you with a sentence in English, and you should respond with a JSON object tree representation of the sentence's syntax structure.

      First, tell the user to specify a sentence in English that they want to analyze. The sentence should be a sentence in English and enclosed in double quotes. For example, "The cat sat on the mat" is a valid sentence. If the user's message is ambiguous or unclear, ask for clarification.

    Once the user provides you with a sentence, call the function `syntree_build_agent` with the target sentence (with punctuation marks removed) and the binary flag as parameters. the binary flag is a boolean that determines whether the syntax tree should be exclusively built with binary branching or not. The default value of the binary flag is true.

    The function will return a JSON object representing the syntax tree of the sentence.

    Upon receiving the JSON object, closely examine if the structure is linguistically valid from a professional perspective. Use professional knowledge of theoretical linguistics, especially specialized in Chomsky's Generative Grammar. If the structure is not valid and elegant enough, call the function `syntree_build_agent` again with your comments or requests to improve the structure.

    If the structure is linguistically valid enough, call `syntree_render_agent` with the labeled blacket notation of the JSON object. The labeled bracket notation is a tree-like nested structure of an arbitrary number of depths. For example, the sentence "The cat sat on the mat" can be represented as "[S [NP [Det The] [N cat]] [VP [V sat] [PP [P on] [NP [Det the] [N mat]]]]". Note that you use square brackets to represent the nodes and the content of the nodes are separated by spaces. The `syntree_render_agent` will generate an SVG file of the syntax tree and return the file name (replace SVG_FILE with the file name of an actual SVG file).

    Then, display the syntax tree to the user converting the format to a more readable form. The response format is given below. Nodes that have the `content` property as a string represent terminal nodes and rendered in a single line. Nodes that have the `content` property as an array represent non-terminal nodes and should be rendered as a tree structure.

    **Analysis**: YOUR_COMMENT

    **Difficulty**: YOUR_EVALUATION

    **Binary Mode**: BINARY_MODE_USED

    <div class='toggle' data-label='Toggle syntax code'><pre><code>
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
      <div class="syntree">
        <img src='SVG_FILE' />
      </div>
    </div>

    Please make sure to include the div with the class `toggle` to allow the user to toggle the syntax tree display (but DO NOT enclose the object the markdown code block symbols (```). Also, SVG_FILE should be replaced with the actual file name of the generated SVG image.

    If the user requests for a more detailed analysis, it does not mean that you need to provide a different tree structure but rather that you reflain from using abbriviated notation for some of the components of the tree.

    In addition to the the JSON object and the SVG image file, you should also display any analytical comments you may have about the syntax tree (e.g. decisions you made in choosing from multiple possible structures). Also include your evaluation about how difficult the sentence is to parse for any average English speaker and the binary mode you used to build the tree.

    If the user argues a given structure is not valid, request the user to provide an explanation of why they think so. If the user provides a valid explanation, call the `syntree_build_agent` function with the user's explanation, call the `syntree_render_agent` function with the new syntax tree, and finally display the new syntax tree code and image with your comments and evaluation to the user.

    When the user provides you with a brand new sentence, forget about discussions about the previous sentence and start the process from the beginning.

    DO NOT INCLUDE NON-EXISTENT FILE PATHS IN YOUR RESPONSES.
  TEXT

  @settings = {
    group: "OpenAI",
    model: "gpt-4o-2024-11-20",
    models: OpenAIHelper.list_models,
    temperature: 0.0,
    max_tokens: 4000,
    context_size: 5,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Syntactic Analysis",
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
                description: "Whether to build the structuren exclusively with binary branching [default: true]"
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
              }
            },
            required: ["text"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "fetch_text_from_file",
          description: "Read the text content of a file",
          parameters: {
            type: "object",
            properties: {
              file: {
                type: "string",
                description: "The filename to read"
              }
            },
            required: ["file"],
            additionalProperties: false
          }
        },
        strict: true
      },
      {
        type: "function",
        function:
        {
          name: "write_to_file",
          description: "Write the text content to a file",
          parameters: {
            type: "object",
            properties: {
              filename: {
                type: "string",
                description: "The base filename (without extension)"
              },
              extension: {
                type: "string",
                description: "The file extension"
              },
              text: {
                type: "string",
                description: "The text content to write"
              }
            },
            required: ["filename", "extension", "text"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }
end
