# Workflow Viewer — Internal Architecture

The Workflow Viewer visualises each MDSL app's internal pipeline as an interactive node graph using maxGraph. It is rendered inside an inline collapsible panel below the app selector.

## Node Types

| Type | Heading | Position | Colour | Description |
|------|---------|----------|--------|-------------|
| `input` | User Input | Flow (center) | Blue | Shows input types (Text, Image, PDF) |
| `prompt` | System Prompt | Flow (center) | Purple | Expandable to show prompt excerpt |
| `model` | Model name | Flow (center) | Green | Expandable to show parameters |
| `response` | Response | Flow (center) | Blue | Shows output types (Text Output, HTML Output) |
| `toolGroup` | Tools | Side (right of Model) | Orange | Collapsible tool groups |
| `agent` | Agent name | Side (right of Model) | Red | Expandable to show backend model |
| `feature` | Features | Side (right of Model) | Grey | Enabled feature flags |
| `history` | Message History | Side (left of Response) | Yellow | Always present; conversation loop source |
| `context` | Monadic Context | Side (left of Response) | Yellow | Only when `context_schema` has fields |

### History vs Context Separation

- **Message History** (`type: 'history'`): Always present. Represents the conversation log. Has a feedback edge to User Input. No arrow from Response (infrastructure, not directional).
- **Monadic Context** (`type: 'context'`): Only shown for monadic apps with `context_schema` fields. Has a directional arrow from Response (extraction flow) and a feedback edge to User Input. During `context_update`, only this node pulses via `setStage('context')`.

Both share the same yellow colour (Context palette) since they are conceptually related.

## Layout Algorithm

### Three-Phase Rendering

1. **Phase 1** — Insert all nodes and flow edges into the graph
2. **Phase 2** — Run `HierarchicalLayout` on flow nodes only (side nodes hidden)
3. **Phase 3** — Position side nodes relative to their parent flow node, then resolve overlaps

### Overlap Resolution

After Phase 3 positioning, `resolveOverlaps(cellMap, graphData)` runs:

- Collects all nodes and marks flow nodes as immovable, side nodes as movable
- Iteratively (max 10 passes) sorts by Y, checks pairwise horizontal+vertical overlap
- Pushes overlapping side nodes downward by `OVERLAP_GAP` (12px)
- Stops when no movement occurs (stable state)

This prevents expanded nodes (e.g., tall Tools or expanded Model) from overlapping with adjacent nodes.

### Feedback Edges

The `feedbackEdges` array (not a single edge) creates L-shaped orthogonal routes from left-side nodes back to User Input:

- History feedback: offset 40px left of the leftmost node
- Context feedback (when present): offset 60px left (additional 20px per index)

## Real-time Highlighting

`setStage(stage)` highlights nodes progressively along the flow chain:

| Stage | Active Nodes | Edge Animation |
|-------|-------------|----------------|
| `input` | Input | — |
| `prompt` | Input, Prompt | Input→Prompt |
| `model` | Input, Prompt, Model | Input→Prompt→Model |
| `tools` | Input, Prompt, Model, Tools | + Model→Tools |
| `response` | Input, Prompt, Model, Response | Input→Prompt→Model→Response |
| `context` | Response, Context | Node pulse only (no edge highlight) |
| `done` | (all cleared) | — |

The `context` stage only pulses the Monadic Context node. The Response→Context edge is never highlighted to avoid rendering artefacts with side-edge waypoints.

## Label Formatting

`titleCase()` handles display labels with acronym awareness:

```javascript
var ACRONYMS = { pdf: 'PDF', html: 'HTML', api: 'API', url: 'URL', tts: 'TTS', stt: 'STT', abc: 'ABC' };
```

- Input/output types: `titleCase` applied (e.g., "pdf" → "PDF", "text" → "Text")
- Feature names: `titleCase` after underscore-to-space conversion
- Tool/agent names: Same treatment

## Backend Integration

### Graph API (`GET /api/app/:name/graph`)

Returns JSON with app pipeline data. Key normalization in `wv_extract_features`:

- `pdf_vector_storage` and `pdf_upload` are normalized to `pdf` (matching `BadgeBuilder.normalize_feature_names`)
- `input_types` also checks these aliases for PDF capability detection

### Feature Flags

`wv_extract_features` checks these flags: `websearch`, `monadic`, `image`, `pdf`, `jupyter`, `mermaid`, `mathjax`, `abc`, `image_generation`, `easy_submit`, `auto_speech`, `initiate_from_assistant`. Only truthy values appear in the Features node.

## Files

| File | Role |
|------|------|
| `public/js/monadic/workflow-viewer.js` | Main IIFE module (graph data, rendering, interaction) |
| `public/css/workflow-viewer.css` | Styles, animations, dark theme |
| `test/frontend/workflow-viewer.test.js` | Jest tests with maxGraph mock |
| `lib/monadic.rb` | Backend graph API endpoint and feature extraction |
