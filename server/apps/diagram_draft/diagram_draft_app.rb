# frozen_string_literal: false

require "tempfile"
require "open3"

class DiagramDraft < MonadicApp
  def icon
    "<i class='fas fa-project-diagram'></i>"
  end

  def description
    "This application hep you visualize data leveraging mermaid.js. Give any data you have and the agent will choose the best diagram type and provide the mermaid code for it, from which you can create a diagram."
  end

  def initial_prompt
    text = <<~TEXT
      You are tasked with data visualization, utilizing mermaid.js to create diagrams and charts that effectively represent data. Typically, the user presents nodes, edges, and labels to specify a graph structure. But other diagram types supported by Mermaid.js are also available."

      Respond to the user's request in the language in which the user speaks or writes.

      Limit the number of the diagram you create to one.

      If the user does not provide data to visualize, create a simple example to visualize.

      Decide which diagram type to use. Use only one of these diagram types. To create a line chart, use `xychart-beta` closely following the examples and do not try to make it more complex than necessary. 

      Remember the indentation and the number of spaces in the mermaid code are important. The mermaid code should be indented either with 4 spaces or 2 spaces.

      The diagram types are:

      - `graph`
      - `C4Context`
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
      - `timeline`
      - `xychart-beta`
      - `sankey-beta`
      - `mindmap`

      Then call `mermaid_examples(DIAGRAM_TYPE)` to retrieve basic examples of any diagram type you're using. Do not use the data from the examples directly. Use the examples to understand the syntax and structure of the mermaid code.

      Finally, respond with the mermaid diagram code using the following HTML format:

      <div class="mermaid-code">
        <pre>
          <code>Mermaid code goes here (without "mermaid" tags and Markdown code block)</code>
        </pre>
      </div>

      Here are very important notes:

      - The diagram dimensions should be less than 1800x600 pixels either horizontally or vertically. Do not use a diagram size larger than this.
      - Be careful not to use brackets and parentheses in flowcharts. Avoid using brackets and parentheses directly in the mermaid code. Escape characters: \[ ] for brackets to show a box and \( ) for parentheses to show a rounded box.
      - Use English for IDs, class names and labels, and avoid using special characters in them.
      - Do not use spalces or quotes in the IDs and class names.

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
      "mermaid": true,
      "file": true,
      "tools": [
        {
          "type": "function",
          "function":
          {
            "name": "mermaid_examples",
            "description": "Get the examples of a specific mermaid diagram type with code examples.",
            "parameters": {
              "type": "object",
              "properties": {
                "diagram_type": {
                  "type": "string",
                  "description": "the type of the mermaid diagram"
                }
              },
              "required": ["diagram_type"]
            }
          }
        }
      ]
    }
  end

  def mermaid_examples(hash)
    diagram_type = hash[:diagram_type]
    diagram_types = ["graph", "C4Context", "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2", "erDiagram", "journey", "gantt", "pie", "quadrantChart",
      "requirementDiagram", "gitGraph", "sankey-beta", "timeline", "xychart-beta", "mindmap"]

    begin
      if diagram_types.include?(diagram_type)
        file_path = File.join(__dir__, "examples", "#{diagram_type}.md")
        if File.exist?(file_path)
          diagram_type_content = File.read(file_path)

          <<~DOCS
            #{diagram_type_content}
          DOCS
        else
          "Example file not found for the diagram type: #{diagram_type}."
        end
      else
        "No example found for the diagram type: #{diagram_type}."
      end
    rescue StandardError => e
      "An error occurred while reading examples for the diagram type: #{diagram_type}. Error: #{e.message}"
    end
  end
end
