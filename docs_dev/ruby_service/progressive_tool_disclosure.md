# Progressive Tool Disclosure (PTD)

An app can hide some of its tools until the model asks for them. Hidden tools are listed by name in the description of a `request_tool` tool; calling `request_tool("<skill>")` makes them visible for the rest of the session.

## Shared Tool Groups

`MonadicSharedTools::Registry` (`lib/monadic/shared_tools/registry.rb`) defines the shared groups in `TOOL_GROUPS`. Each entry has:

- `module_name`: the module with the tool methods (`lib/monadic/shared_tools/<group>.rb`)
- `tools`: names, descriptions and parameters
- `default_hint`: the unlock hint shown in the skill menu
- optional `visibility: 'conditional'` and `available_when` (a lambda), which only drive the availability badge in the UI

`Registry.safe_groups` (`SAFE_GROUPS`) lists the read-only groups.

## MDSL

```ruby
tools do
  import_shared_tools :file_operations, visibility: "always"
  import_shared_tools :python_execution            # conditional by default
  reachable_skills :web_search_tools, :image_analysis
  reachable_skills :safe                           # every group in Registry.safe_groups
end
```

- `import_shared_tools(*groups, visibility: "conditional", unlock_hint: nil)` defines each tool of the group in the app. A tool already defined under the same name is skipped.
- With `visibility: "conditional"`, each tool gets `unlock_when tool_request: "<group>"` and the hint, and `request_tool` is added to the app.
- `reachable_skills` imports groups as conditional.
- `image_analysis`, `video_analysis` and `audio_transcription` are imported only when the app's provider can do that analysis itself (`ProviderCapabilities`).
- The imported groups are recorded in `imported_tool_groups`, and the generated class includes each group's module; the app list sent to the UI adds `available` from `Registry.available?` for the badges (`badge-renderer.js`).

App-defined tools use the same settings inside `define_tool`: `visibility` (`always`, `conditional`, `hidden`), `unlock_when tool_request: "…"` or `unlock_when event: "…"`, and `unlock_hint`.

## Runtime

`Monadic::Utils::ProgressiveToolManager` (`lib/monadic/utils/progressive_tool_manager.rb`) works on the app's `progressive_tools` metadata (`always_visible`, `conditional`, `all_tool_names`). State is kept per app in `session[:progressive_tools][app_name]` (`unlocked`, `triggered_events`, `scanned_count`).

- `visible_tools` returns the always-visible tools, the unlocked tools, and every tool the metadata does not mention. Before filtering it unlocks:
  - tools named by a `request_tool("…")` text in messages it has not scanned yet;
  - tools whose `unlock_when event:` has been triggered (`trigger_event`).
- `handle_request_tool` runs the `request_tool` call: the argument may be a group key or a single conditional tool name. It returns `Unlocked: …`, and sends a `tool_unlocked` message to the session's connection.
- `annotate_request_tool` appends the skill menu (one line per still-locked group, each telling the model to call `request_tool("<key>")`) to the description of `request_tool` in the request.
- When the session's web search is off, the `web_search_tools` tools are removed, left out of the menu, and cannot be unlocked.
- The `library_search` tool follows the Knowledge Base toggle (`library_rag_enabled`), however the app imports it and also for apps without progressive metadata: it is added while the toggle is on and removed while it is off. It is never in the menu and cannot be unlocked.

The vendor helpers call `visible_tools` and `annotate_request_tool` when they build the tools of a request.

## Adding a Shared Group

1. Write the module in `lib/monadic/shared_tools/<group>.rb` (namespace `MonadicSharedTools`).
2. Add the entry to `TOOL_GROUPS` with `module_name`, `tools` and `default_hint`; add `visibility: 'conditional'` and `available_when` if the UI should show availability.
3. Import it in the MDSL. The generated app class includes the group's module.

## Tests

- `spec/unit/utils/progressive_tool_manager_spec.rb`
- `spec/unit/utils/progressive_tools_persistence_spec.rb`
- `spec/unit/dsl/progressive_tools_metadata_merge_spec.rb`
- `spec/unit/shared_tools/registry_planning_verification_spec.rb`

## Related Documentation

- `docs/advanced-topics/monadic_dsl.md`
- [apps_tools_inventory.md](apps_tools_inventory.md)
