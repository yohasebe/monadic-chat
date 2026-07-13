# Contributing to Monadic Chat

Thanks for your interest in improving Monadic Chat. This guide covers how to
set up a development environment, run the tests, and submit changes.

## Getting started

Monadic Chat is an Electron desktop app wrapping a Ruby (Rack) backend and a
set of Docker services. Docker Desktop must be running for most workflows.

```bash
npm install            # install Node/Electron dependencies
npm start              # launch the Electron app (manages Docker containers)
```

For backend-only work you can run the server on the host without the Electron
shell:

```bash
rake server:debug      # runs the Ruby server locally; peer containers stay in Docker
```

## Running the tests

**Frontend (Jest):**

```bash
npm test
```

**Ruby (RSpec):** run from `docker/services/ruby/` — the project-root Gemfile
lacks `csv` (removed from the Ruby 3.4+ stdlib), so specs must use that
directory's bundle:

```bash
cd docker/services/ruby
bundle exec rspec spec/unit          # unit specs (no Docker required)
bundle exec rspec spec/integration   # integration (needs provider APIs / Docker)
```

Provider-facing tests assert on shape and invariants rather than exact
response strings, and treat transient provider errors as non-fatal — please
follow that style for new API tests.

## Linting and style

```bash
npx eslint .                              # JavaScript
cd docker/services/ruby && bundle exec rubocop   # Ruby
```

- Ruby uses 2-space indentation.
- Code, comments, and test data are English-only. (Language/translation
  resource files are the deliberate exception.)
- The frontend has no jQuery — use the DOM helpers defined in
  `dom-helpers.js` (`$id`, `$show`, `$hide`, `$on`, …) rather than
  `document.getElementById` directly.

## Documentation

Public documentation lives in `docs/` and is maintained in both English and
Japanese (`docs/ja/`). **Every change under `docs/` must have a matching
change in `docs/ja/`**, with the same heading structure. Verify before
committing:

```bash
npm run test:docs-parity
```

## Commits and pull requests

- Keep commit subjects short, in English, and in the imperative mood
  (e.g. "Fix web-search toggle race"). One-line messages are strongly
  preferred; put detail in the PR description.
- Open a pull request against the `dev` branch. Describe what changed and why,
  and note any manual verification you performed.
- Make sure `npm test` and the relevant RSpec suites pass before requesting
  review.

## Reporting issues

Please open a GitHub issue with your OS, Monadic Chat version (Help → About, or
`docker/services/ruby/lib/monadic/version.rb`), and clear reproduction steps.
For UI or rendering problems, a screenshot and the browser/console output help.

## License

By contributing, you agree that your contributions will be licensed under the
project's [Apache License 2.0](LICENSE).
