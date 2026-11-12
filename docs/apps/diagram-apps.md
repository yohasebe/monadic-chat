# Diagram & Visualization Apps

Apps that turn descriptions and data into diagrams — Mermaid and Draw.io charts, linguistic syntax trees, and LaTeX/TikZ concept visualizations.

## Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize your data with [Mermaid.js](https://mermaid.js.org/) diagrams. Provide your data or instructions, and the AI writes the Mermaid code and shows the diagram in the [work screen](../basic-usage/web-interface.md#work-screen) beside the chat. The diagram is a `.mmd` file in the chat's folder of the shared folder; the reply names its path, and a line under the reply shows it again. **Drawn** and **Source** switch between the diagram and its code.

In the chat, a diagram is shown as an image with **Download SVG**; the switch above it shows the Mermaid code. Settings written inside a diagram (`%%{init: …}%%` or front matter) are not used: the diagram is not drawn, and the reason is shown. Mermaid code in a reply of any app is drawn this way.

**Key Features:**
- **Diagram type selection**: The AI chooses a diagram type that suits your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, and others)
- **Render check**: Before the diagram is shown, it is drawn with Mermaid.js in a browser in the Selenium container. If Mermaid reports an error, the AI corrects the code and tries again
- **Visual check**: The AI looks at a screenshot of the drawn diagram to find layout problems before it answers
- **Error analysis**: When the code has syntax errors, the AI analyzes them and suggests fixes
- **Web search**: The AI can look up the Mermaid.js documentation for less common diagram types

Mermaid Grapher supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Create Draw.io diagrams by describing your requirements. The AI writes Draw.io XML, checks and repairs its structure, and shows the diagram in the [work screen](../basic-usage/web-interface.md#work-screen) beside the chat. The diagram is a `.drawio` file in the chat's folder of the shared folder; the reply names its path, and a line under the reply shows it again. **Drawn** and **Source** switch between the diagram and its XML.

**Key Features:**
- **XML check and repair**: The generated Draw.io XML is checked, and common structural problems are repaired
- **Diagram types**: Flowcharts, UML diagrams (class, sequence, activity), ER diagrams, network diagrams, org charts, mind maps, BPMN, Venn diagrams, wireframes, and more
- **Files**: Each diagram is a new `.drawio` file, so earlier diagrams stay. It can be opened in Draw.io for further editing. Ask for a file name and place to save a copy elsewhere in the shared folder

DrawIO Grapher is available for the providers marked in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

Generate linguistic syntax trees from sentences in multiple languages. The app analyzes grammatical structure and draws the tree with [RSyntaxTree](https://yohasebe.github.io/rsyntaxtree/). Key features include:

- Support for multiple languages, including English, Japanese, and Chinese. A sentence in a language written right to left is drawn mirrored, with its first word at the right edge.
- The words of the sentence on one row, each joined to its node by a dashed line.
- Movement drawn as an arrow from the trace or copy to the landing site, and a phrase left unanalyzed drawn under a triangle.
- SVG output that can be edited in vector graphics editors.

The tree is shown on the [work screen](../basic-usage/web-interface.md#work-screen) beside the chat as an SVG image with a transparent background. The SVG is saved in the chat's folder in the shared folder (`conversations/…/artifacts/`), and the reply gives its path. Ask for the LaTeX source to get the tree as a `.tex` file (LaTeX forest) beside the SVG; the movement arrows are not in it.

Syntax Tree supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize concepts and relationships by describing them in natural language. The app uses LaTeX/TikZ to draw many kinds of diagrams. Key features include:

- **Diagram types**: Mind maps, flowcharts, org charts, network diagrams, timelines, Venn diagrams, 3D plots (scatter plots, surfaces), and more.
- **Natural language input**: Describe what you want to visualize.
- **Domains**: Business, educational, scientific, and technical diagrams.
- **Languages**: Text in many languages, including Chinese, Japanese, and Korean.

The diagrams are saved to the shared folder as SVG and PNG. The SVG can be edited in any vector graphics editor.

Concept Visualizer needs LaTeX: turn on **Install LaTeX (minimal set for diagrams)** in **Actions → Install Options** and rebuild the Python container. Availability by provider is shown in the [availability table](../basic-usage/basic-apps.md#app-availability).
