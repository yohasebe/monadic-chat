# Internal Developer Documentation (docs_dev)

This folder hosts internal developer documentation that SHOULD be read by assistants (Codex CLI, Claude Code) when loading this repository.

- Entry points assistants should scan (if present):
  - `docs_dev/notes/overview.md`
  - `docs_dev/notes/import-startup-guidelines.md`
  - All other Markdown files under `docs_dev/`

Guidance for assistants
- Treat docs here as the freshest engineering context (import/startup flow, race-condition mitigations, current experiments).
- Do not surface these notes verbatim to end users unless explicitly requested.
- If a file referenced below is missing, ask the maintainer to restore it from backup.

Restoration note
- Some internal documentation was inadvertently removed during a prior cleanup. If you maintain a backup, please restore to:
  - `docs_dev/notes/` (general notes and design)
  - `docs_dev/architecture/` (frontend/backend architecture)
  - `docs_dev/provider/` (provider capabilities and mappings)
  - `docs_dev/mdsl/` (MDSL internals)
  - `docs_dev/testing/` (test architecture and guides)
  - `docs_dev/experiments/` (experimental apps e.g., music app demos)

