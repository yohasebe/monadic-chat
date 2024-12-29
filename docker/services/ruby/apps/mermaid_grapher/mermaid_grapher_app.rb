class MermaidGrapher < MonadicApp
  include OpenAIHelper

  icon = "<i class='fas fa-project-diagram'></i>"

  description = <<~TEXT
    This application hep you visualize data leveraging mermaid.js. Give any data you have and the agent will choose the best diagram type and provide the mermaid code for it, from which you can create a diagram. <a href='https://yohasebe.github.io/monadic-chat/#/basic-apps?id=mermaid-grapher' target='_blank'><i class="fa-solid fa-circle-info"></i></a>
  TEXT

  initial_prompt = <<~TEXT
    You are tasked with creating visual representations of data structures using mermaid.js. The user will provide nodes, edges, and labels to outline a graph structure.

    Respond to the user's request in the language in which the user speaks or writes.

    Limit the diagram creation to one per request. Before generating the diagram, ensure that you have checked the documentation for the specific diagram type the user is requesting using the `mermaid_documentation` function explained below.

    If no specific data is provided, generate a simple graph or flowchart example.

    Pay attention to the indentation and spacing in the mermaid code, which are crucial for correct rendering. Use either 4 or 2 spaces for indentation.

    Diagram types include:
      - `graph`
      - `flowchart`
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
      - `C4Context`
      - `mindmap`
      - `timeline`
      - `sankey-beta`
      - `xychart-beta`
      - `block-beta`
      - `packet-beta`
      - `kanban`
      - `architecture-beta`

    Use the `mermaid_documentation` function with the `diagram_type` parameter to get basic examples for the diagram type you're using. Please do not copy the examples directly; use them to understand syntax and structure.

    Respond with the mermaid diagram code in the following HTML format:

    <div class="mermaid-code" label="Show/Hide Mermaid code">
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
    group: "OpenAI",
    model: "gpt-4o-2024-11-20",
    temperature: 0.0,
    top_p: 0.0,
    max_tokens: 4000,
    initial_prompt: initial_prompt,
    easy_submit: false,
    auto_speech: false,
    app_name: "Mermaid Grapher",
    description: description,
    icon: icon,
    initiate_from_assistant: false,
    pdf: false,
    mermaid: true,
    image: true,
    tools: [
      {
        type: "function",
        function:
        {
          name: "mermaid_documentation",
          description: "Get the documentation of a specific mermaid diagram type with code examples.",
          parameters: {
            type: "object",
            properties: {
              diagram_type: {
                type: "string",
                enum: [
                  "flowchart",
                  "sequenceDiagram",
                  "classDiagram",
                  "stateDiagram",
                  "entityRelationshipDiagram",
                  "userJourney",
                  "gantt",
                  "pie",
                  "quadrantChart",
                  "requirementDiagram",
                  "gitgraph",
                  "c4",
                  "mindmap",
                  "timeline",
                  "sankey",
                  "xyChart",
                  "block",
                  "packet",
                  "kanban",
                  "architecture"
                ],
                description: "the type of the mermaid diagram"
              }
            },
            required: ["diagram_type"],
            additionalProperties: false
          }
        },
        strict: true
      },
    ]
  }

  def mermaid_documentation(diagram_type: "graph")
    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  end
end
