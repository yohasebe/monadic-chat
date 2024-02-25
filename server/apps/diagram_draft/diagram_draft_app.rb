# frozen_string_literal: false

require "tempfile"
require "open3"

class DiagramDraft < MonadicApp
  def icon
    "<i class='fas fa-project-diagram'></i>"
  end

  def description
    "This app AI chatbot designed to suggest preliminary visualizations of data through diagrams and charts. It leverages mermaid.js for the generation of these visual aids. Upon receiving a user request, the chatbot selects the most suitable diagram type for the presented data and refers to the Mermaid documentation for code examples to optimally illustrate the data."
  end

  def initial_prompt
    text = <<~TEXT
      You are tasked with data visualization, utilizing mermaid.js to create diagrams and charts that effectively represent data. Respond to the user's request in the language in which the user speaks or writes. You do not have to draw a diagram or chart if the user is asking for something other than a diagram or chart.

      Decide which diagram type to use for the data the user provides or you create from the following types: `flowchart`, `sequenceDiagram`, `classDiagram`, `stateDiagram-v2`, `erDiagram`, `journey`, `gantt`, `pie`, `quadrantChart`, `requirementDiagram`, `gitGraph`, `sankey-beta`, `timeline`, `xychart-beta`, `mindmap`. Do not use any diagram types other than these. Only use the listed diagram types. For example, instead of line or linechart, use xychart-beta for line charts.

      Use `mermaid_documentation(DIAGRAM_TYPE)` to retrieve basic examples and the documentation of any diagram type you’re unsure about. Limit this call to once per user request. Even if you are sure about the diagram type, you should use this function to make sure you are up to date with the latest specifications of the diagram type.

      In your response, use the following format to include a diagram with the mermaid code:

          <div class="sourcecode-toggle">show/hide sourcecode</div>
          <div class="sourcecode">
            <pre>
              <code>
                MERMAID_CODE
              </code>
            </pre>
          </div>

          <div class="diagram">
            <mermaid>
              MERMAID_CODE
            </mermaid>
          </div>

      Do not include the mermaid code anywhere outside the above format.

      The diagram dimensions should be less than 1000x600 pixels either horizontally or vertically. Do not use a diagram size larger than this.

      Do not confuse different diagram types. For example, do not use the `flowchart` type with the code for the `sequenceDiagram` type. Always check the documentation for the correct usage of the diagram type.

      Be careful not to use brackets and parentheses in the mermaid code. Avoid using brackets and parentheses directly in the mermaid code. For labels requiring these, employ escape characters: \[ \] for brackets, \( \) for parentheses.

      Do not use the \`\`\` delimiters around the mermaid code in your response.

      The user may provide data to visualize below. User-provided data for visualization will be clearly marked as `TARGET DOCUMENT: TITLE`.
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0125",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 10,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Diagram Draft",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "mathjax": true,
      "mermaid": true,
      "file": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "mermaid_documentation",
            "description": "Get the documentation of a specific mermaid diagram type with code examples.",
            "parameters": {
              "type": "object",
              "properties": {
                "diagram_type": {
                  "type": "string",
                  "description": "the type of the mermaid diagram",
                }
              },
              "required": ["diagram_type"]
            }
          }
        }
      ]
    }
  end

  def mermaid_documentation(hash, num_retrials: 3)
    diagram_type = hash[:diagram_type]
    diagram_types = [
      "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2",
      "erDiagram", "journey", "gantt", "pie", "quadrantChart",
      "requirementDiagram", "gitGraph", "sankey-beta", "timeline",
      "xychart-beta", "mindmap"
    ]

    begin
      if diagram_types.include?(diagram_type)
        file_path = File.join(__dir__, "documentation", "#{diagram_type}.md")
        if File.exist?(file_path)
          diagram_type_content = File.read(file_path)

          <<~DOCS
            #{diagram_type_content}
          DOCS
        else
          "Documentation file not found for the diagram type: #{diagram_type}."
        end
      else
        "No documentation found for the diagram type: #{diagram_type}."
      end
    rescue => e
      "An error occurred while reading documentation for the diagram type: #{diagram_type}. Error: #{e.message}"
    end
  end
end
