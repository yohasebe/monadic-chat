class MermaidGrapher < MonadicApp
  def mermaid_documentation(diagram_type: "graph")
    fetch_web_content(url: "https://mermaid.js.org/syntax/#{diagram_type}.html")
  end
end
