# CHANGELOG Style

`CHANGELOG.md` is read by users, shown in the documentation (`docs/changelog.md` includes it) and cut into GitHub release notes by `rake release:github`.

## Version Line

Each entry starts with `- [Month, Year] <version>`. `rake release:github` finds a release's section by this exact line, and `rake version:*` renames the top entry while its version is unreleased. Entries are separated by one blank line, newest first. A version appears in one heading only: the release task takes the first heading with that version, and an entry ends at the next top-level `- [` line.

## Groups

Under the version line, up to five groups in this order, each only when it has items. Groups are second-level bullets, items third-level:

```markdown
- [October, 2026] 1.0.0-beta.44
  - Security
    - …
  - Changes you may notice
    - …
  - New
    - …
  - Fixed
    - …
  - For developers
    - …
```

| Group | Holds |
|---|---|
| Security | What is fixed, one line each |
| Changes you may notice | Behavior that changed and could surprise someone: something removed, a new requirement, a different default, a setting that is ignored |
| New | Features |
| Fixed | Bugs, written as what works now |
| For developers | Rake tasks, MCP tools, MDSL, build and test tooling, file layout that a developer or a script relies on |

## Items

- One line in the present tense, about what the user sees or does now.
- An action the user must take (delete files, re-upload, a minimum OS) is in bold, in any group; nothing else is.
- Security items say what is fixed, not how it could be misused, which versions were affected, or how it was found.
- No causes, no history ("used to", "since"), no internal names (classes, source files, constants), no provider-side internals.
- Names are the ones users meet: UI labels in backticks as they appear, settings, files under `~/monadic`, app names, MCP tool names, rake tasks.
- A container to rebuild goes at the end in parentheses: `(rebuild the Python container)`.
- Products by their marketed names, not API model IDs.
- Changes that concern only the project's internals are not listed.

Under For developers, the names a contributor writes are fine: entries and flags in `model_spec.js`, MDSL settings, rake tasks, files an app folder holds. MCP tools that clients call (Monadic Conduit) are a feature and go under New; changes to how the MCP server answers go under For developers.
