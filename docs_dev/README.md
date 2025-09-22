# Monadic Chat Developer Docs (Internal)

This documentation is for Monadic Chat contributors and maintainers. It complements the public user docs under `./docs` and is committed to the repo (no external docsify publishing).

## Core Topics

- [JS Console Log Modes](js-console.md) — How to view and control logs in development
- [Server Debug Mode](server-debug-mode.md) — `rake server:debug` behavior and lifecycle
- [Dev vs Production Paths](electron-paths.md) — Electron path handling and pitfalls
- [External JS Libraries](external-libs.md) — How to register and vendor assets with `assets.sh`/`assets_list.sh`
- [Testing Guide](testing.md) — Test categories, goals, and commands
- [Logging Guide](logging.md) — Log locations, types, and enabling extra logging

## Additional Resources

- [Docker Architecture](docker-architecture.md) — Container structure, lifecycle, and management
- [Common Issues](common-issues.md) — Frequent problems and their solutions
- [Backlog](backlog.md) — Pending clean-up tasks and follow-ups

## Quick Start for New Developers

1. Clone the repository and install dependencies:
   ```bash
   npm install
   bundle install
   ```

2. Set up your API keys in `~/monadic/config/env`:
   ```
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=sk-ant-...
   ```

3. Start development server:
   ```bash
   rake server:debug  # Uses local Ruby, other containers via Docker
   ```

4. Run the Electron app:
   ```bash
   npm start  # or electron .
   ```

5. Run tests:
   ```bash
   rake spec_unit  # Fast, no external dependencies
   RUN_API=true PROVIDERS=openai rake spec_api:smoke  # With real API
   ```

## Lint Checks

- Run `npm run lint:deprecated-models`（または `rake lint:deprecated_models`）で `docs/`・`docs_dev/`・`translations/` から旧モデル名を検出できます。必要に応じて `config/deprecated_model_terms.txt` を更新してください。
