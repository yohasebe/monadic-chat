# Diagram & Visualization Apps

Apps that turn descriptions and data into diagrams — Mermaid and Draw.io charts, linguistic syntax trees, and LaTeX/TikZ concept visualizations.

## Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize your data with [Mermaid.js](https://mermaid.js.org/) diagrams. Provide your data or instructions, and the AI writes the Mermaid code and the diagram is shown in the chat.

**Key Features:**
- **Diagram type selection**: The AI chooses a diagram type that suits your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, and others)
- **Render check**: Before the diagram is shown, it is drawn with Mermaid.js in a browser in the Selenium container. If Mermaid reports an error, the AI corrects the code and tries again
- **Visual check**: The AI looks at a screenshot of the drawn diagram to find layout problems before it answers
- **Error analysis**: When the code has syntax errors, the AI analyzes them and suggests fixes
- **Web search**: The AI can look up the Mermaid.js documentation for less common diagram types

Mermaid Grapher supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Create Draw.io diagrams by describing your requirements. The AI writes Draw.io XML, checks and repairs its structure, and saves the diagram to the shared folder.

**Key Features:**
- **XML check and repair**: The generated Draw.io XML is checked, and common structural problems are repaired
- **Diagram types**: Flowcharts, UML diagrams (class, sequence, activity), ER diagrams, network diagrams, org charts, mind maps, BPMN, Venn diagrams, wireframes, and more
- **Preview**: The diagram is drawn in a browser in the Selenium container, and a PNG preview is shown in the chat
- **Files**: The `.drawio` file is saved to the shared folder and can be opened in Draw.io for further editing. A PNG preview (`drawio_preview_<timestamp>.png`) is saved as well

Unless you give a file name, the diagram is saved as `diagram.drawio`, replacing the previous one. Ask for a file name to keep several diagrams.

DrawIO Grapher is available for the providers marked in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

Generate linguistic syntax trees from sentences in multiple languages. The app analyzes grammatical structure and draws the tree with LaTeX and tikz-qtree. Key features include:

- Support for multiple languages, including English, Japanese, and Chinese.
- SVG output that can be edited in vector graphics editors.
- Linguistic notation that follows syntactic theory.

The trees are shown in the chat as SVG images with transparent backgrounds and saved to the shared folder.

Syntax Tree needs LaTeX: turn on **Install LaTeX (minimal set for diagrams)** in **Actions → Install Options** and rebuild the Python container. Availability by provider is shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize concepts and relationships by describing them in natural language. The app uses LaTeX/TikZ to draw many kinds of diagrams. Key features include:

- **Diagram types**: Mind maps, flowcharts, org charts, network diagrams, timelines, Venn diagrams, 3D plots (scatter plots, surfaces), and more.
- **Natural language input**: Describe what you want to visualize.
- **Domains**: Business, educational, scientific, and technical diagrams.
- **Languages**: Text in many languages, including Chinese, Japanese, and Korean.

The diagrams are saved to the shared folder as SVG and PNG. The SVG can be edited in any vector graphics editor.

Concept Visualizer needs LaTeX: turn on **Install LaTeX (minimal set for diagrams)** in **Actions → Install Options** and rebuild the Python container. Availability by provider is shown in the [availability table](../basic-usage/basic-apps.md#app-availability).
