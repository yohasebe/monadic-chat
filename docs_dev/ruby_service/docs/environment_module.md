# Environment Module

`Monadic::Utils::Environment` (`lib/monadic/utils/environment.rb`) detects whether the Ruby code runs in the Ruby container or on the host (development mode) and resolves paths for both.

## Detection

`in_container?` returns, in order: `ENV["IN_CONTAINER"] == "true"` when the variable is set, the `IN_CONTAINER` constant when defined, otherwise whether `/.dockerenv` exists.

## Paths

`resolve_path(container_path, local_path = nil)` returns `container_path` in the container; on the host it returns `local_path`, or `container_path` with `/monadic` replaced by `~/monadic`.

| Method | Container | Host |
|---|---|---|
| `config_path` | `/monadic/config` | `~/monadic/config` |
| `env_path` | `/monadic/config/env` | `~/monadic/config/env` |
| `data_path`, `shared_volume` | `/monadic/data` | `~/monadic/data` |
| `state_path` | `/monadic/state` | `~/monadic/state` |
| `scripts_path`, `apps_path`, `helpers_path` | `data_path` + `scripts`, `apps`, `helpers` | same, under `~/monadic/data` |
| `log_path` | `/monadic/log` | `~/monadic/log` |
| `command_log_file`, `extra_log_file`, `jupyter_log_file` | `command.log`, `extra.log`, `jupyter.log` in `log_path` | same |
| `system_script_dir` | `/monadic/scripts` | `docker/services/ruby/scripts` in the source tree |

The config env file is read through `Monadic::Utils::EnvFile` (`lib/monadic/utils/env_file.rb`), by the server (`lib/monadic.rb`, for both ENV and CONFIG), `rake server:debug`, the test runner and the help build script; nothing else loads it into the environment (a spec checks there is no `Dotenv.load`/`parse` elsewhere). It parses the file itself: `KEY=value` lines, optional `export`, plain, single-quoted or double-quoted values; nothing is expanded or run (`${VAR}` and `$(...)` stay text). Only the settings the code reads from ENV go there (`ENV_KEYS`, `*_API_KEY`, `*_DEFAULT_MODEL`; `spec/unit/utils/env_file_spec.rb` checks the list against the code), and a value the shell set is kept. Settings that decide where requests go or what program runs (`REFUSED`: proxies, `QDRANT_URL`, `EXTRACTOR_URL`, `EMBEDDINGS_URL`, `MONADIC_OP_CLI`, ...) are not taken for ENV or CONFIG, nor are names of that form (`REFUSED_PATTERNS`: ending in `_URL`, `_HOST`, `_ENDPOINT`, `_PROXY`, `_SOCKET`, `_CMD`, `_COMMAND`, `_BIN`, ..., or in `_PATH`, `_DIR`, `_FILE` unless the key is in `PATH_KEYS`), so a setting added later needs a check in `EnvFile` before the file can set it (a spec checks that no key the code reads from CONFIG by name is lost this way); a port (`PORT_KEYS`) must be a number from 1 to 65535; a setting that names a file (`PATH_KEYS`) must be an absolute path to an existing file or folder outside the shared folder, and is passed on as its real path. The names of settings left out are printed (never values).

`state_path` holds server-owned records outside the shared folder. It is mounted into the Ruby container only. One server writes it: at start the server takes a numbered mark in `server.owner/` (`Workspace::ServerOwner`) before reading the ledger, and does not start when another server holds it. A mark left by a server that stopped is followed only when that server is known to have stopped (another start of the container, or its process gone; from the host, Docker answering that the Ruby container has stopped). Ledger changes run inside `ServerOwner.writing`, and a stopping server lets them finish before it notes in its mark that it has stopped. The ledger (`ledger.json`) is checked on every read and before every save (`Workspace::LedgerSchema`: ids of each kind, chats and workspaces that point at each other, attachment paths inside their chat's folder, size and sha256 on a ready attachment); a ledger that is not JSON, not of that form, or written by a newer version raises `Ledger::Syntax`, `Shape` or `Newer` (all `Ledger::Unreadable`), and a change that would leave it out of form is not saved. Fields and collections it does not know are kept. The ledger is version 2 (`artifacts` and `publications` added; `publications` is taken only empty). A version 1 ledger (beta.42, beta.43) is read in the version 2 form without being changed; the first change keeps its bytes as they were in `ledger.json.v1.bak` (an existing backup of other bytes is left, and these go under another name), settled on disk with its folder before the ledger is replaced, and then saves version 2 (`Ledger::NotUpgraded` and nothing changed when the backup fails). Every save settles the folder after the replacement (a folder that cannot be synced is not taken as synced); when that fails, the process writes no more to that ledger, under any path that names it (`Ledger::Unsettled`), until the server starts again, and an attachment whose ready record was put in place this way keeps its file. Nothing is put back automatically: going back to the backup loses what was recorded since, and a version 1 server refuses a version 2 ledger. Before the first start of version 2, servers of an earlier version (in the container or run from the host) must be stopped: they do not know `ServerOwner`.

What a run makes (today the WebVTT and SRT subtitles of a timed transcript) is kept as an artifact in `state_path/artifacts/<artifact id>/` (`Workspace::Artifacts.store!`), where only the server writes, and recorded in the ledger with the size and sha256 of the bytes the server wrote. A run (`Workspace::Jobs`) belongs to the chat the ledger gives for its workspace (`Jobs.create!(workspace_id)`) or, for runs asked for from outside any chat (the MCP server), to a folder set aside for them (`LedgerSchema::OUTSIDE_ROOTS`); the artifact records that owner, the job, its kind and `copy_path`, the place of the copy written in the run folder for people and other programs to read. `copy_path` only says where a copy was written: more than one record can name the same path, and a record is never found by it. Nothing trusts that copy: the subtitles' public copies are made from the kept bytes, and subtitles that could not be kept are neither copied to the run folder nor published. No artifact is made while the ledger is no longer written or the server is stopping; a kept file is removed when its record cannot be made, and kept when the record may have been saved but not settled.

## Log Rotation

`rotate_log(file)` renames `file` to `file.1` (shifting older files up to `file.<max>`) once it exceeds `LOG_ROTATE_MAX_BYTES` (default 5 MB). `LOG_ROTATE_MAX_FILES` (default 5) sets the number of files. Errors are ignored.

## Usage

```ruby
Monadic::Utils::Environment.in_container?
Monadic::Utils::Environment.data_path
```

A class that includes the module also gets the methods as class methods.
