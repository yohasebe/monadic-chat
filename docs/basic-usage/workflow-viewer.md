# Workflow Viewer

The Workflow Viewer draws a live diagram of the currently selected app: how your input flows through the system prompt and model to the response, and which tools, agents, and features the app can use. Open it from the **Workflow Viewer** control in the System Settings panel.

## Display modes

| Mode | Button | Behavior |
|------|--------|----------|
| Hidden | eye-slash icon | The viewer is closed. |
| Inline | panel icon | The diagram is embedded in the settings area. |
| Floating | external-link icon | The diagram opens as a movable, resizable panel. |

The toolbar inside the viewer provides zoom in/out, fit-to-view, SVG download, and close.

## Reading the diagram

Nodes are color-coded by role — the legend at the bottom lists the categories (Input/Response, Speech, Prompt, Model, Tool, Agent, Feature, Context). The vertical spine shows the conversation flow (input → prompt → model → response, plus speech input/output when enabled); side nodes show the app's tools, agents, features, and Monadic context schema.

### Tools and skill groups

The **Tools** node lists the app's own tools and its shared skill groups. Groups can be expanded or collapsed by clicking them.

- **🔒 (locked)** — a *conditional* skill group: the app can reach these tools, but they are offered to the AI only after it requests them with `request_tool` (see [Tool Groups](../advanced-topics/tool-groups.md)).
- **🔓 (unlocked)** — the conversation has already unlocked this group; its tools are available for the rest of the session.
- **✓** — an individual tool that has been unlocked this session.

When the AI unlocks a skill mid-conversation, the diagram updates automatically, so the chart always reflects the session's actual capability set. Unlocked skills are also saved with a session export and restored on import.

### Which apps can extend their tools?

An app's extendable (conditional) skills are declared in its recipe, so the set differs per app:

- `import_shared_tools :group, visibility: "conditional"` in the app's tools block makes the group requestable on demand; `visibility: "always"` includes it from the start.
- `reachable_skills :group1, :group2` (or `reachable_skills :safe` for the curated read-only pool) is the shorthand form.
- **Knowledge Base retrieval** (`library_search`) is added automatically as a conditional skill to tool-capable apps and becomes usable when the *Use Knowledge Base for retrieval* toggle is on.

If a skill group does not appear in the Tools node at all, the app cannot acquire it — asking the AI to request it will not succeed.
