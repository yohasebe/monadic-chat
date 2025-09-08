Title: Improvement Topics (High-Level Roadmap)

Scope
- Coarse‑grained areas to guide medium‑term improvements. Technical details and specific designs will evolve and be captured separately when implemented.

Topics

1) Error Handling & Logging
- Establish consistent, structured error logging (with secret masking).
- Define a small set of exception types for common failure classes.
- Prefer logging in rescue paths over silent failure; keep behavior unchanged.

2) Security Hardening
- Review shell execution points; provide a safe wrapper (Open3 + Shellwords) for new code.
- Input/path validation helpers for file operations.
- Periodic dependency and secret scans (advisory Rake tasks, opt‑in by maintainers).

3) Performance & Scalability
- Streaming I/O for large PDF processing.
- Connection pooling for database operations with pg/pgvector.
- Background jobs for heavy or long‑running tasks.
- Lightweight performance monitoring and slow‑path logging.

4) Architecture & Modularity
- Split monolithic components (e.g., monadic.rb) into focused modules.
- Extract service objects for PDF storage/vector store orchestration.
- Centralize common adapter behaviors (error patterns, retries) into shared concerns.

5) Testing Strategy
- Favor structure‑oriented assertions for API responses; avoid brittle string equality.
- Maintain unified runner with API‑level toggles; extend artifacts (index summaries, HTML summaries).
- Keep tests updated when behavior is correct; adjust implementation only for true defects.

6) Observability
- Structured application logs across major flows.
- Optional tracing hooks for critical paths (websocket, PDF ingestion, API calls).
- Simple dashboards/reports for local development (no external dependencies required).

7) Dependency Management
- Consolidate overlapping HTTP libraries where practical.
- Regular advisory audits (e.g., bundler audit task); avoid disruptive lockstep upgrades.

8) Documentation
- Internal maintainers’ notes for operational runbooks and ADR‑style rationale.
- Public developer docs kept concise and task‑oriented; advanced details in internal docs.

Notes
- All initiatives prioritize backward compatibility and staged adoption.
- Changes that affect behavior or external interfaces will include migration notes and opt‑out paths.

