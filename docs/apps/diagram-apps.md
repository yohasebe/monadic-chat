# Diagram & Visualization Apps

Apps that turn descriptions and data into diagrams — Mermaid and Draw.io charts, linguistic syntax trees, and LaTeX/TikZ concept visualizations.

## Mermaid Grapher

![Mermaid Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize your data with [Mermaid.js](https://mermaid.js.org/) diagrams. Simply provide your data or instructions, and the AI will generate and render the appropriate Mermaid code for the diagram.

**Key Features:**
- **Live browser preview**: Diagrams render in a real browser visible via noVNC (`http://localhost:7900`), so you can watch changes in real time
- **Automatic diagram type selection**: The AI chooses the best diagram type for your data (flowchart, sequence, class, state, ER, Gantt, pie, Sankey, mindmap, etc.)
- **Real-time validation**: Diagrams are validated using Selenium and the actual Mermaid.js engine before being displayed
- **Visual self-verification**: The AI captures screenshots of rendered diagrams and visually inspects the output to catch layout issues or rendering errors before responding to the user
- **Error analysis**: When syntax errors occur, analyzes error patterns and provides fix suggestions
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Web search integration**: Can fetch the latest Mermaid.js documentation and examples for unfamiliar diagram types

**Usage Tips:**
- Simply describe what you want to visualize, and the AI will create the appropriate diagram
- Open `http://localhost:7900` in a separate browser window (or use the noVNC menu item in Electron) to watch diagrams render live
- All preview images are saved as `mermaid_preview_[timestamp].png` in your shared folder

Mermaid Grapher supports each provider shown in the [availability table](../basic-usage/basic-apps.md#app-availability).


## DrawIO Grapher

![DrawIO Grapher app icon](../assets/icons/diagram-draft.png ':size=40')

Create Draw.io diagrams by describing your requirements. The agent generates Draw.io XML, validates the structure, and renders a live preview in the browser via noVNC.

**Key Features:**
- **Live browser preview**: Diagrams render in a real browser visible via noVNC (`http://localhost:7900`), so you can watch changes in real time
- **Automatic XML validation and repair**: The agent validates the generated Draw.io XML and attempts to repair common structural issues
- **Wide diagram type support**: Flowcharts, UML diagrams (class, sequence, activity), ER diagrams, network diagrams, org charts, mind maps, BPMN, Venn diagrams, wireframes, and more
- **Visual self-verification**: The AI captures screenshots of rendered diagrams and visually inspects the output to catch layout issues or rendering errors before responding to the user
- **Preview generation**: A PNG preview image is saved to your shared folder for easy access
- **Downloadable .drawio files**: The generated `.drawio` file is saved to your shared folder and can be imported into Draw.io for further editing

**Usage Tips:**
- Simply describe the diagram you need, and the AI will create the appropriate Draw.io XML
- Open `http://localhost:7900` in a separate browser window (or use the noVNC menu item in Electron) to watch diagrams render live
- All preview images are saved as `drawio_preview_[timestamp].png` in your shared folder

DrawIO Grapher is available for the providers marked in the [availability table](../basic-usage/basic-apps.md#app-availability). File generation fidelity depends on each provider's tooling support.


## Syntax Tree

![Syntax Tree app icon](../assets/icons/syntax-tree.png ':size=40')

Generate linguistic syntax trees from sentences in multiple languages. The app analyzes grammatical structure and creates visual tree diagrams using LaTeX and tikz-qtree. Key features include:

- Support for multiple languages, including English, Japanese, and Chinese.
- Editable SVG output for further modification in vector graphics editors.
- Professional linguistic notation that follows syntactic theory standards.

The generated syntax trees are displayed as SVG images with transparent backgrounds.


Syntax Tree availability matches the [availability table](../basic-usage/basic-apps.md#app-availability).


## Concept Visualizer :id=concept-visualizer

![Concept Visualizer app icon](../assets/icons/diagram-draft.png ':size=40')

Visualize concepts and relationships by describing them in natural language. The app uses LaTeX/TikZ to create a wide variety of diagrams, including mind maps, flowcharts, network diagrams, and even 3D plots. Key features include:

- **Wide variety of diagram types**: Create mind maps, flowcharts, org charts, network diagrams, timelines, Venn diagrams, 3D visualizations, and more.
- **Natural language input**: Simply describe what you want to visualize.
- **Multiple domains**: Suitable for business, educational, scientific, and technical diagrams.
- **Multi-language support**: Handles text in various languages, including CJK (Chinese, Japanese, Korean).
- **Professional output**: Generates high-quality, editable SVG diagrams suitable for presentations and publications.
- **3D capabilities**: Supports 3D scatter plots, surfaces, and other three-dimensional visualizations.

The generated diagrams are saved to your shared folder and can be modified in any vector graphics editor.

Concept Visualizer supports the providers listed in the [availability table](../basic-usage/basic-apps.md#app-availability).
