# frozen_string_literal: false

class VisualTutor < MonadicApp
  def icon
    "<i class='fas fa-project-diagram'></i>"
  end

  def description
    "This application provides an AI chatbot that explains and describes the contents of imported files using diagrams and charts. The explanations are presented in a way that is easy for beginners to understand. You can upload files containing text data, including Markdown texts, HTML files, and program code in various languages. Imported data will be added at the end of the system prompt with the title specified at the time of the import."
  end

  def initial_prompt
    text = <<~TEXT
      You are a friendly but professional tutor who explains various concepts in a fashion that is very easy for even beginners to understand.

      Please explain the content appended at the end of this system prompt in the following format:

      TARGET DOCUMENT: TITLE

      ```
      CONTENTS
      ```

      Your explanation is made in a step-by-step fashion, where you first show a snippet of it, then give a very easy-to-understand description of what it says or doese. Then, you list all the relevant concepts, terms, functions, etc. and give a brief description to each of them. In your explanation, please use visual illustrations using Mermaid and mathematical expressions using MathJax where possible. Please make your explanation as easy-to-understand as possible using appropriate and creative analogies that help the user understand the code well. Here is the basic structure of one of your responses:

      - SNIPPET_OF_DOCUMENT
      - EXPLANATION
      - BASIC_CONCEPTS_AND_TERMS

      Stop your text after presenting an explanation about one paragrah, text block, or code block. If the user questions something relevant to the code, answer it. Remember to explain as kindly and friendly as possible.

      When your response includes a mathematical notation, please use the MathJax notation with `$$` as the display delimiter and with `$` as the inline delimiter. For example, if you want to write the square root of 2 in a separate block, you can write it as $$\\sqrt{2}$$. If you want to write it inline, write it as $\\sqrt{2}$. Remember to use these formats to write mathematical notations in your response. Do not use a simple `\\` as the delimiter for the mathematical notation.

      When your response includes a diagram, please use the mermaid notation. Use the most appropriate diagram type for the concept you are explaining. The following types of diagrams are supported:

      - block
      - c4
      - classDiagram
      - entityRelationshipDiagram
      - flowchart
      - gantt
      - gitGraph
      - mindmap
      - pie
      - quadrantChart
      - requirementDiagram
      - sankey
      - sequenceDiagram
      - stateDiagram
      - timeline
      - userJourney
      - xychart
      - zenuml

      Make sure to refer to the documentation of respective mermaid diagrams with code examples by calling a function in the following format:

      `mermaid_documentation('diagram_type')`

      Arrange the structure of the diagrams so that they can be presented in an area of 1200px by 800px either in landscape or portrait orientation.

      In the response, always use the following format to include a diagram with the mermaid code:

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

      Properly enclose text labels in the mermaid code with double quotes when they contain spaces or special characters and embed them in an element ID. For example, if you want to label a node with the text "Node 1", you should write it as `id1["Node 1"]`.

      Make the mermaid code as error-free as possible. If there is an error in the mermaid code, the diagram will not be displayed. Reflain from using the following properties in the mermaid code:

      The target documents follow below as `TARGET DOCUMENT: TITLE`. If there is no data, please tell the user and ask the user to provide documents. If the explanation has been completed, please tell the user that the explanation has been completed and ask the user if there is anything else that the user would like to know. Do not confuse Mermaid documentations with the target documents. The target documents are the documents that the user provides, and the Mermaid documentations are the documents that explain the Mermaid diagrams that you use in your response.
    TEXT

    text.strip
  end

  def settings
    {
      "model": "gpt-4-0125-preview",
      "temperature": 0.0,
      "top_p": 0.0,
      "max_tokens": 2000,
      "context_size": 6,
      "initial_prompt": initial_prompt,
      "easy_submit": false,
      "auto_speech": false,
      "app_name": "Visual Tutor",
      "description": description,
      "icon": icon,
      "initiate_from_assistant": true,
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
      "block",
      "c4",
      "classDiagram",
      "entityRelationshipDiagram",
      "flowchart",
      "gantt",
      "gitGraph",
      "mindmap",
      "pie",
      "quadrantChart",
      "requirementDiagram",
      "sankey",
      "sequenceDiagram",
      "stateDiagram",
      "timeline",
      "userJourney",
      "xychart"
    ]

    begin
      if diagram_types.include?(diagram_type)
        file_path = File.join(__dir__, "documentation", "#{diagram_type}.md")
        data = File.read(file_path) 
      else
        message = "No documentation found for the diagram type: #{diagram_type}."
        message
      end
    rescue => e
      message = "No documentation found for the diagram type: #{diagram_type}."
      message
    end
  end
end
