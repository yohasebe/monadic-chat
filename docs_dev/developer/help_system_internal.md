# Internal Documentation in the Monadic Help Database

## Overview

The Help data format supports both public documentation (`docs/`) and internal
developer documentation (`docs_dev/`). Every point is tagged with an
`is_internal` payload field. Read APIs exclude internal points by default; the
installation feature accepts only explicitly public points.

The shipped database contains **public documentation only**: `docs/`, plus the
root `README.md` and `CHANGELOG.md`. `rake help:build` passes `--public-only`,
and `HelpDumpGuard` refuses to package a dump that carries internal points —
from both `scripts/stage_docker_payload.rb` and the `beforePack` hook that the
npm build scripts go through. Developers can generate a dump containing
`docs_dev/` with `rake help:build_internal`, but both packaging and
`Monadic::Help::ValidatedDump` reject that dump. It cannot be installed through
the Help data installation feature, even with `DEBUG_MODE=true`.

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

All content read APIs on `HelpEmbeddings` default to `include_internal: false`:
`find_closest_text`, `find_closest_text_multi`, `find_closest_doc`, `list_titles`,
`get_text_snippets`, `search`, `get_stats`, `get_unique_categories`, and
`get_by_category`. They require `is_internal == false`; points with a missing
flag are excluded along with internal points. Visibility filters are combined
with language, document, and category filters. Item results and statistics also
respect the visibility of their parent documents.

For example, `find_closest_text` applies a Qdrant payload filter:

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
`include_internal:` wins. This controls visibility only for data already present;
it does not install internal documentation. The public dump contains no internal
points, and the installer rejects internal dumps regardless of `DEBUG_MODE`.

Every Help tool performs its complete read inside
`Monadic::Help.installation.with_search`, including embedding, item retrieval,
and parent document retrieval. The yielded connection must not escape the block.
When search is unavailable, tools return structured installation guidance rather
than creating collections or importing data.

## Rake Tasks

Defined in `rakelib/help.rake`.

### help:build
Regenerates the dump from public documentation only, passing `--public-only`.
This is the task a release build runs. Starts the embeddings container if port
8002 is not already reachable, and stops it afterwards only if this task was the
one that started it — and not at all when `KEEP_VECTOR_SERVICES=true`.

### help:build_internal
Same, but passes `--include-internal` so `docs_dev/` is covered as well. For
local development only — the resulting dump is rejected by packaging and the
Help data installer.

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

`Monadic::Help::Installation` installs data only after an explicit user action.
The startup loader performs no import or collection bootstrap. The entry points
are the Monadic Chat Help panel and **Monadic Chat Info → Help Data**. Neither
viewing the status nor installing requires a provider API key.

- `GET /help/database` renders the standalone panel.
- `GET /help/database/status` returns a read-only snapshot without creating lock
  files or collections.
- `POST /help/database/install` starts a background worker and returns HTTP 202
  with `install_id`. A busy lock returns HTTP 409 with `retryable: true`; the
  caller must retry explicitly. Parameters are rejected with HTTP 400 and
  cross-origin requests with HTTP 403.

The endpoint accepts another explicit installation even when the same dump is
already installed, and replaces the data again. It does not require a
confirmation dialog.

#### Installation states

| State | Meaning | Searchable |
|---|---|---|
| `not_installed` | Neither help collection exists and there is no failed installation attempt | No |
| `legacy` | Both help collections exist but neither has installation records; reinstall to establish a verified version | No |
| `installing` | An installation holds the job lock | No in the status response |
| `installed` | Matching completion records and exact counts have been verified | Yes |
| `update_available` | The installed data is verified, but its SHA-256 differs from the bundled file | Yes, until replacement begins |
| `failed` | An installation failed without a usable database, or records/counts are missing, inconsistent, or incomplete | No |
| `unavailable` | The vector store cannot be reached or queried | No |

If the bundled file cannot be fingerprinted, a verified installed database remains
searchable: `bundled_match` is `null` and `bundled_error` carries the reason.
A failure during validation also preserves a previously healthy database and
reports the failed attempt through `last_attempt`.

#### Coordination and replacement

Instances and processes targeting the same database must share the coordination
directory: `/monadic/data/.help-installation` in the container or
`~/monadic/data/.help-installation` on the host. `job.lock` serializes installers;
`readers.lock` protects the full duration of Help reads using `flock`. Lock files
are never unlinked because lock ownership is tied to their inode. Progress is
persisted in `progress.json` with file and directory `fsync` and atomic rename.

The worker runs these steps:

1. **Validate** the entire dump with `ValidatedDump` before any database mutation:
   format version, embedding model/dimension, the two required collections,
   unique unsigned integer IDs, explicitly public payloads, finite vectors, and
   valid item-to-document references. The SHA-256 and imported points come from
   the same file read. Healthy existing data remains readable through
   `with_search` during this stage, although status reports `installing`.
2. **Prepare** by refusing new search leases and waiting for active readers to
   finish. Persist `database_invalid: true` before the first destructive change.
3. **Replace** only `help_docs` and `help_items`: delete and recreate each
   collection, then attach installation metadata with `state: installing`.
   `library_*` and `pdf_*` collections are untouched.
4. **Load** points in batches. Each upsert must report `completed` before progress
   advances.
5. **Verify counts** for both collections with exact counts against the dump.
6. **Record completion** on both collections with `state: completed` and
   `loaded_at`. Read the records back, verify equality with the intended record,
   and **verify exact counts again**.
7. **Finish** by persisting the completed journal with `database_invalid: false`,
   then release the locks so search can resume.

A failed or interrupted replacement stays unsearchable until an explicit retry
completes. There is no automatic rollback or retry. The durable invalidation
also covers an interruption after both completion records are written but before
final verification. An abandoned running journal is reported as a failed attempt
when the job lock is no longer held.

#### Installation metadata and new dumps

Both collections store the same record under the `monadic_help_installation`
metadata key:

- `install_id`, `dump_sha256`, `dump_version`
- `embedding_model`, `embedding_dimension`
- `expected_docs`, `expected_items`
- `state`, `loaded_at`, `exported_at` (the dump's export time)

The version is `1`, the model is `intfloat/multilingual-e5-base`, and the vector
dimension is 768. Readiness requires compatible, matching completion records and
exact point counts; `exported_at` is informational. The installed SHA-256 is
compared with the current dump to detect an available update.

To deliver changed public documentation, run `rake help:build`, then rebuild and
recreate the Ruby container with the new dump, or supply a readable mounted dump
via `HELP_DATA_DUMP`. Finally, use the panel to install or update. Rebuilding,
restarting, or changing the dump path alone does not replace installed data.
Do not delete the Qdrant volume: it also contains user data.

## Configuration

| Variable | Effect |
|---|---|
| `DEBUG_MODE=true` | Includes `docs_dev/` at build time (unless `--public-only`); defaults Help tool reads to include internal points already present |
| `HELP_DATA_DUMP` | Overrides the dump path used for explicit installation and update detection |
| `HELP_CHUNK_SIZE` | Characters per chunk (default 3000) |
| `HELP_OVERLAP_SIZE` | Overlap between chunks (default 500) |
| `HELP_CHUNKS_PER_RESULT` | Chunks per search result (default 3) |
| `KEEP_VECTOR_SERVICES=true` | Leaves the embeddings container running after a build |

`DEBUG_MODE` controls build inclusion and the Help tools' default read visibility.
`--public-only` overrides it for builds; an explicit `include_internal:` overrides
it for reads. It does not bypass installation validation or the search
availability checks. `help:build_internal` therefore does not provide a supported
installation path for internal content.

`Monadic::Help.installation` resolves the default dump to
`/monadic/help_data/help_db.json` inside the container and
`docker/services/ruby/help_data/help_db.json` in host development.
`HELP_DATA_DUMP` overrides either default. Installation instances are constructed
on demand; availability and search connections are not cached.

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
