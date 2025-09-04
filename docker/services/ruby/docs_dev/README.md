# Internal Developer Documentation (docs_dev)

This folder hosts internal developer documentation that SHOULD be read by assistants (Codex CLI, Claude Code) when loading this repository.

## Entry Points

Assistants should scan (if present):
- `docs_dev/notes/overview.md`
- `docs_dev/notes/import-startup-guidelines.md`
- All other Markdown files under `docs_dev/`

## Guidance for Assistants

- Treat docs here as the freshest engineering context (import/startup flow, race-condition mitigations, current experiments)
- Do not surface these notes verbatim to end users unless explicitly requested
- If a file referenced below is missing, ask the maintainer to restore it from backup

## Directory Structure

- `docs_dev/notes/` - General notes and design decisions
- `docs_dev/architecture/` - Frontend/backend architecture documentation
- `docs_dev/provider/` - Provider capabilities and mappings
- `docs_dev/mdsl/` - MDSL internals and specifications
- `docs_dev/testing/` - Test plans and strategies

## Restoration Note

This directory was recreated after being accidentally removed during repository cleanup.
Original content should be restored from backups if available.
