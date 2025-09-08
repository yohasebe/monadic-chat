Title: Hardening Quick Wins (Safe, No-Behavior Changes)

Scope
- Low-risk improvements that do not change runtime behavior or user-visible features. Suitable for incremental adoption.

Implemented
- Secret masking in debug logs
  - DebugHelper now masks ENV/CONFIG secrets and common key patterns in debug output.
  - Applies only when debugging is enabled; normal execution unaffected.

Proposed (Next)
- Lint guardrails (advisory, non-blocking):
  - RuboCop rule to flag bare `rescue StandardError` without logging.
  - Script to grep for `system/backticks/exec` occurrences to review input sources.
- Security checks (opt-in tasks):
  - Add `bundler-audit` Rake task for offline advisory scans; keep off by default.
  - Add a simple secret scan (regex) in `tmp/` artifacts before sharing.
- Structured exception helper (opt-in):
  - Introduce `DebugHelper.log_exception(e, context: { ... })` as a standard pattern; adopt gradually in rescue blocks.
- Shell execution helpers (opt-in):
  - Provide a small wrapper using `Open3.capture3` with `Shellwords` to be used in new code paths.

Notes
- All items are designed to be non-invasive and off by default (no change in behavior unless explicitly used).
- Larger refactors (service extraction, streaming I/O, connection pools) are tracked separately and will be scheduled with regression plans.

