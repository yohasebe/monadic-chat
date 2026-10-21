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

`state_path` holds server-owned records outside the shared folder. It is mounted into the Ruby container only. One server writes it: at start the server takes a numbered mark in `server.owner/` (`Workspace::ServerOwner`) before reading the ledger, and does not start when another server holds it. A mark left by a server that stopped is followed only when that server is known to have stopped (another start of the container, or its process gone; from the host, Docker answering that the Ruby container has stopped). Ledger changes run inside `ServerOwner.writing`, and a stopping server lets them finish before it notes in its mark that it has stopped.

## Log Rotation

`rotate_log(file)` renames `file` to `file.1` (shifting older files up to `file.<max>`) once it exceeds `LOG_ROTATE_MAX_BYTES` (default 5 MB). `LOG_ROTATE_MAX_FILES` (default 5) sets the number of files. Errors are ignored.

## Usage

```ruby
Monadic::Utils::Environment.in_container?
Monadic::Utils::Environment.data_path
```

A class that includes the module also gets the methods as class methods.
