# frozen_string_literal: false

class DataVisualizer < MonadicApp
  def icon
    "<i class='fas fa-project-diagram'></i>"
  end

  def description
    " This application provides an AI chatbot that visualizes data using diagrams and charts. It uses mermaid.js to generate diagrams and charts. Upon user request, it chooses the most appropriate diagram type for the data and refer to the documentation of the mermaid diagram type with code examples to explain the data most appropriately."
  end

  def initial_prompt
    text = <<~TEXT
      You are a capable data visualizer that uses mermaid.js to create diagrams and charts to visualize data. First, you decide which diagram type to use for the data the user provides or you create among the following types.

      - flowchart: Flowcharts are composed of nodes (geometric shapes) and edges (arrows or lines).
      - sequenceDiagram: A Sequence diagram is an interaction diagram that shows how processes operate with one another and in what order.
      - classDiagram: The class diagram is the main building block of object-oriented modeling.
      - stateDiagram-v2: A state diagram is a type of diagram used in computer science and related fields to describe the behavior of systems.
      - erDiagram:An entity–relationship model (or ER model) describes interrelated things of interest in a specific domain of knowledge.
      - journey: User journeys describe at a high level of detail exactly what steps different users take to complete a specific task within a system, application, or website.
      - gantt: A Gantt chart illustrates a project schedule and the amount of time it would take for any one project to finish.
      - pie: A pie chart (or a circle chart) is a circular statistical graphic, which is divided into slices to illustrate numerical proportion.
      - quadrantChart: A quadrant chart is a visual representation of data that is divided into four quadrants.
      - requirementDiagram: A Requirement diagram provides a visualization for requirements and their connections, to each other and other documented elements.
      - gitGraph: A Git Graph is a pictorial representation of git commits and git actions(commands) on various branches.
      - sankey-beta: A sankey diagram is a visualization used to depict a flow from one set of values to another.
      - timeline:A timeline is a type of diagram used to illustrate a chronology of events, dates, or periods of time.
      - xychart-beta: In the context of mermaid-js, the XY chart is a comprehensive charting module that encompasses various types of charts that utilize both x-axis and y-axis for data representation
      - mindmap: A mind map is a diagram used to visually organize information into a hierarchy, showing relationships among pieces of the whole.
      - block-beta: A block diagram is a diagram of a system in which the principal parts or functions are represented by blocks connected by lines that show the relationships of the blocks.
      - C4Context: The C4 model is an "abstraction-first" approach to diagramming software architecture, based upon abstractions that reflect how software architects and developers think about and build software.

      Then you call a function `mermaid_documentation(diagram_type)` and read the documentation returned from the function call about that particular mermaid diagram type. Next you provide the user with the mermaid code constructed according to the information you have got from the documentation. Always check the documentation for the details of the syntax and the usage of the diagram type.

      Do not use any document types other than the ones listed above. If the user's reques cannot be expressed with any of the above diagram types, you should inform the user about the situation and ask for a different request.

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

      Do not use the \`\`\` delimiters for the mermaid code.

      In your respopnse, use the language in which the users speaks or writes. 

      The user may provide data to visualize. If there is user data, it is marked with `TARGET DOCUMENT: TITLE` below. 
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-3.5-turbo-0125",
      "frequency_penalty": 0.1,
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 6,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Data Visualizer",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": false,
      "pdf": false,
      "mathjax": true,
      "mermaid": true,
      "file": true ,
      "function_call": { "name": "mermaid_documentation" },
      "functions": [{
        "name" => "mermaid_documentation",
        "description" => "Get the documentation of a specific mermaid diagram type with code examples.",
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
      }]
    }
  end

  def mermaid_documentation(hash, num_retrials: 3)
    diagram_type = hash[:diagram_type]
    diagram_types = [
      "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2",
      "erDiagram", "journey", "gantt", "pie", "quadrantChart",
      "requirementDiagram", "gitGraph", "sankey-beta", "timeline",
      "xychart-beta", "mindmap", "block-beta", "C4Context"
    ]

    begin
      if diagram_types.include?(diagram_type)
        file_path = File.join(__dir__, "documentation", "#{diagram_type}.md")
        if File.exist?(file_path)
          diagram_type_content = File.read(file_path)
          basic_example_path = File.join(__dir__, "documentation", "examples.md")
          basic_examples = File.read(basic_example_path)
          results = diagram_type_content + "\n\n" + basic_examples
          results
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
