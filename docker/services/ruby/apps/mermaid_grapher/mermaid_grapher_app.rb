require "tempfile"
require "open3"

class MermaidGrapher < MonadicApp
  icon = "<i class='fas fa-project-diagram'></i>"

  description = <<~TEXT
    This application hep you visualize data leveraging mermaid.js. Give any data you have and the agent will choose the best diagram type and provide the mermaid code for it, from which you can create a diagram.
  TEXT

  initial_prompt = <<~TEXT
    You are tasked with creating visual representations of data structures using mermaid.js. The user will provide nodes, edges, and labels to outline a graph structure.

    Respond to the user's request in the language in which the user speaks or writes.

    Limit the diagram creation to one per request.

    If no specific data is provided, generate a simple graph or flowchart example.

    Pay attention to the indentation and spacing in the mermaid code, which are crucial for correct rendering. Use either 4 or 2 spaces for indentation.

    Diagram types include:
      - `graph`
      - `flowchart`
      - `C4Context`
      - `sequenceDiagram`
      - `classDiagram`
      - `stateDiagram-v2`
      - `erDiagram`
      - `journey`
      - `gantt`
      - `pie`
      - `quadrantChart`
      - `requirementDiagram`
      - `gitGraph`
      - `timeline`
      - `xychart-beta`
      - `sankey-beta`
      - `mindmap`

    Use `mermaid_examples(DIAGRAM_TYPE)` to get basic examples for the diagram type you're using. Please do not copy the examples directly; use them to understand syntax and structure.

    Respond with the mermaid diagram code in the following HTML format:

    <div class="mermaid-code">
      <pre>
        <code>Mermaid code goes here (without "mermaid" tags and Markdown code block)</code>
      </pre>
    </div>

    Important notes:
    - Keep diagram dimensions within 1800x600 pixels.
    - Avoid using brackets and parentheses directly in the mermaid code. Use escape characters: \[ ] for brackets and \( ) for parentheses.
    - Use English for IDs, class names, and labels. Avoid special characters.
    - Do not use spaces or quotes in IDs and class names.

    User-provided data for visualization will be marked as `TARGET DOCUMENT: TITLE`.
  TEXT

  @settings = {
    model: "gpt-4o-2024-08-06",
    temperature: 0.0,
    top_p: 0.0,
    max_tokens: 4000,
    context_size: 20,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Mermaid Grapher",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: false,
    mermaid: true,
    file: true,
    image: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "mermaid_examples",
          description: "Get the examples of a specific mermaid diagram type with code examples.",
          parameters: {
            type: "object",
            properties: {
              diagram_type: {
                type: "string",
                enum: ["graph",
                       "C4Context",
                       "flowchart",
                       "sequenceDiagram",
                       "classDiagram",
                       "stateDiagram-v2",
                       "erDiagram",
                       "journey",
                       "gantt",
                       "pie",
                       "quadrantChart",
                       "requirementDiagram",
                       "gitGraph",
                       "sankey-beta",
                       "timeline",
                       "xychart-beta",
                       "mindmap"],
                description: "the type of the mermaid diagram"
              }
            },
            required: ["diagram_type"],
            additionalProperties: false
          }
        },
        strict: true
      }
    ]
  }

  def mermaid_examples(diagram_type: "graph")
    file_path = File.join(__dir__, "examples", "#{diagram_type}.md")
    if File.exist?(file_path)
      diagram_type_content = File.read(file_path)

      <<~DOCS
        #{diagram_type_content}
      DOCS
    else
      "Example file not found for the diagram type: #{diagram_type}."
    end
  rescue StandardError => e
    "An error occurred while reading examples for the diagram type: #{diagram_type}. Error: #{e.message}"
  end
end
