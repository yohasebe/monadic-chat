# Ruby Service Development Guide

## Setup

- Ruby 3.4 (the Ruby image uses `ruby:3.4.7-slim-bookworm`), Bundler, and Docker for the peer containers.
- Install the gems in `docker/services/ruby`:

```bash
cd docker/services/ruby
bundle install
```

Run specs from `docker/services/ruby` with its own bundle; the root `Gemfile` lacks gems the specs need.

The gems come from `docker/services/ruby/Gemfile.lock`, which is tracked: the host, CI and the Ruby image (`BUNDLE_FROZEN=true` in the Dockerfile) install the same versions, each checked against its checksum. To change a gem, edit `monadic.gemspec` and make the lock file again in the image's Ruby, so the Linux and macOS variants and their checksums are written:

```bash
cd docker/services/ruby
docker run --rm -v "$PWD":/w -w /w ruby:3.4.7-slim-bookworm sh -c \
  'bundle lock --update <gem> && bundle lock --add-checksums'
bundle install
```

## Running Tests

```bash
cd docker/services/ruby
bundle exec rspec spec/unit                    # unit specs, no Docker
bundle exec rspec spec/integration             # provider APIs / containers
bundle exec rspec spec/unit/scripts/office2txt_minimal_spec.rb   # one file
```

From the project root, `rake spec` runs the Ruby specs and `rake spec:quick` runs unit and integration specs without system specs. See `docs_dev/test_runner.md` and `docs_dev/test_quickref.md` for the other tasks.

## Spec Directories

| Directory | Contents |
|---|---|
| `spec/unit/` | Isolated specs; external services are stubbed |
| `spec/integration/` | Specs that call provider APIs or containers |
| `spec/system/` | Full application flows |
| `spec/e2e/` | Flows through the local server's WebSocket, without real provider APIs |
| `spec/performance/` | Native web search timing |

## Script Specs

- Ruby scripts are tested on the host with temporary files.
- Python scripts are tested through the Python container, with test files in the shared folder (`~/monadic/data`); the specs remove what they create.

## Code Style

```bash
cd docker/services/ruby
bundle exec rubocop
```
