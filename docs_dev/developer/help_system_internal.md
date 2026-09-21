# Internal Documentation in the Monadic Help Database

## Overview

The Monadic Help database carries both public documentation (`docs/`) and
internal developer documentation (`docs_dev/`). Every point is tagged with an
`is_internal` payload field, and search filters on it.

The shipped database contains **public documentation only**: `docs/`, plus the
root `README.md` and `CHANGELOG.md`. `rake help:build` passes `--public-only`,
and `HelpDumpGuard` refuses to package a dump that carries internal points —
from both `scripts/stage_docker_payload.rb` and the `beforePack` hook that the
npm build scripts go through. Developers who want to search `docs_dev/` too
build a local dump with `rake help:build_internal`; that dump must not be
packaged, and the gate will stop it if it is.

## Architecture

### Storage

Two Qdrant collections hold the help index (`lib/monadic/vector_store/schema.rb`):

- `help_docs` — one point per documentation file
- `help_items` — one point per chunked fragment

Both carry `is_internal` in their payload. Vectors are 768-dimensional with
cosine distance.

### Build

`scripts/utilities/process_documentation.rb` walks both trees:

```ruby
process_language_docs('en', DOCS_PATH, is_internal: false)      # docs/
if include_internal && Dir.exist?(DOCS_DEV_PATH)
  process_language_docs('en', DOCS_DEV_PATH, is_internal: true) # docs_dev/
end
```

Three inputs decide `include_internal`, in this order:

```ruby
include_internal = false if public_only
include_internal ||= (ENV['DEBUG_MODE'] == 'true') unless public_only
```

`--public-only` wins over everything. It exists because `DEBUG_MODE` is
routinely set in a developer shell, and without an explicit override a release
build run from such a shell would quietly produce an internal dump. Omitting
`--include-internal` is not enough.

The dump records what it did in its metadata, so a consumer can check without
scanning every point:

```json
{ "includes_internal": false }
```

The result is written to `docker/services/ruby/help_data/help_db.json`, which
the Ruby image bakes in (`Dockerfile`: `COPY help_data/`).

### Search

`HelpEmbeddings#find_closest_text` applies a Qdrant payload filter:

```ruby
def find_closest_text(text, top_n: 10, include_internal: false)
  filter = include_internal ? nil : without_internal_filter
  ...
end

def without_internal_filter
  { must: [{ key: 'is_internal', match: { value: false } }] }
end
```

The Monadic Help app decides the flag per request
(`apps/monadic_help/monadic_help_tools.rb`):

```ruby
include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?
```

`DEBUG_MODE` is consulted only when the caller passes nothing; an explicit
`include_internal:` wins. So a developer running with `DEBUG_MODE=true` searches
both trees by default; everyone else searches only public documentation.

## Rake Tasks

Defined in `rakelib/help.rake`.

### help:build
Regenerates the dump from public documentation only, passing `--public-only`.
This is the task a release build runs. Starts the embeddings container if port
8002 is not already reachable, and stops it afterwards only if this task was the
one that started it — and not at all when `KEEP_VECTOR_SERVICES=true`.

### help:build_internal
Same, but passes `--include-internal` so `docs_dev/` is covered as well. For
local development only — the resulting dump is rejected at packaging time.

### help:rebuild
Deletes the existing dump first, then runs the same build.

### help:stats
Prints statistics for the current dump.

### help:export
Prints the path of the dump and exits non-zero if the file is missing. It does
not transform or filter anything.

### help:build_dev
Deprecated alias that warns and redirects to `help:build_internal`.

## Distribution

The dump reaches users through two paths, both of which take the file as-is:

- `scripts/stage_docker_payload.rb` lists `help_data/help_db.json` in
  `REQUIRED_BUILD_PRODUCTS`, so it is staged into the Electron package.
- The Ruby image copies `help_data/` during build.

`rakelib/build.rake` skips regeneration when `SKIP_HELP_DB=true`, in which case
whatever dump is already on disk is the one that ships. That is the case the
packaging gate guards. `scripts/help_dump_guard.rb` holds the rules and is
called from two places, because there are two ways to package:

- `scripts/stage_docker_payload.rb` checks the dump in the source tree before
  staging it. This is the Rake path.
- `scripts/before_pack.js`, registered as electron-builder's `beforePack`,
  checks the **staged** copy under `build/app-payload/`. The npm build scripts
  (`npm run build:mac-arm64` and its siblings) run electron-builder directly
  and never invoke the stager, so without this hook they would package whatever
  was staged earlier — or nothing at all, since app-builder-lib only logs
  `file source doesn't exist` for a missing `extraResources` source. A missing
  staged dump therefore fails the build rather than producing an installer with
  no help database.

The guard refuses a dump that carries any point with `is_internal`, that names
a source file no longer in the tree, or whose shape it cannot read — an empty
collection, or points without an id, a payload hash and a boolean
`is_internal`. A point it cannot read is a point it cannot clear for shipping,
so such a dump is refused rather than skipped. A developer
who ran `help:build_internal` and then packaged with `SKIP_HELP_DB=true` gets
stopped rather than shipping the internal dump.

### Loading into an existing installation

`lib/monadic/utils/help_embeddings_loader.rb` imports the dump **only when the
collections are empty**:

```ruby
unless db.data_loaded?
  Monadic::Help::DumpLoader.load(store: db.store, path: dump_path)
end
```

`Monadic::Help::DumpLoader` upserts points and never deletes. Shipping a new
dump therefore does not replace what an existing installation already holds —
old points survive both the "collections are populated" short-circuit and the
upsert. Changing `HELP_DATA_DUMP` to another path does not help either, for the
same reason.

Clearing the collections is therefore only half the job. The container reads
the dump from inside its own image, so a dump you just built on the host is not
visible to it until you deliver it. To search an internal dump locally:

1. Build it: `rake help:build_internal`.
2. Get it where the Ruby process can read it — either rebuild the Ruby image so
   `COPY help_data/` picks up the new file, or mount the file into the
   container and point `HELP_DATA_DUMP` at that path.
3. Clear the `help_docs` and `help_items` collections in Qdrant, so the loader
   stops short-circuiting on `data_loaded?`.
4. Recreate the Ruby container, then search with `DEBUG_MODE=true`. Recreate,
   not restart: `docker restart` keeps the old image, and a new mount or
   `HELP_DATA_DUMP` value only takes effect on a container started with it.

Skipping step 2 just reloads the same public dump that is already in the image.
Do not delete the whole Qdrant volume: `library_*` and `pdf_*` collections hold
user data.

## Configuration

| Variable | Effect |
|---|---|
| `DEBUG_MODE=true` | Includes `docs_dev/` at build time (unless `--public-only`) **and** returns it in search |
| `HELP_DATA_DUMP` | Overrides the dump path read at startup |
| `HELP_CHUNK_SIZE` | Characters per chunk (default 3000) |
| `HELP_OVERLAP_SIZE` | Overlap between chunks (default 500) |
| `HELP_CHUNKS_PER_RESULT` | Chunks per search result (default 3) |
| `KEEP_VECTOR_SERVICES=true` | Leaves the embeddings container running after a build |

`DEBUG_MODE` does double duty: build inclusion and search visibility. The build
half is overridden by `--public-only`; the search half is overridden by passing
`include_internal:` explicitly. Either way, a public dump has nothing internal
to return, so a developer who wants internal search needs a dump built by
`help:build_internal`, delivered to the container, and the collections reloaded
from it (see
[Loading into an existing installation](#loading-into-an-existing-installation)).

## Verifying what a dump contains

```bash
ruby -rjson -e '
  d = JSON.parse(File.read("docker/services/ruby/help_data/help_db.json"))
  d["collections"].each do |name, c|
    n = c["points"].count { |p| p.dig("payload", "is_internal") }
    puts format("%-12s %5d points, %5d internal", name, c["points"].size, n)
  end'
```

## See Also

- [Help System](../../docs/advanced-topics/help-system.md) — public documentation
- `docker/services/ruby/scripts/utilities/process_documentation.rb`
- `docker/services/ruby/lib/monadic/utils/help_embeddings.rb`
- `rakelib/help.rake`
