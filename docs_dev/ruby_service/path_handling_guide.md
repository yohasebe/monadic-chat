# Path Handling Guide

The Ruby code runs in the Ruby container (`/monadic/data` is the shared folder) or, in development mode, on the host (`~/monadic/data`). Python always runs in its container. This page lists the helpers that resolve and check paths in the shared folder.

## Three Kinds of Paths

| Kind | Example | Used for |
|---|---|---|
| Filesystem path | `Monadic::Utils::Environment.data_path` + `report.pdf` | File I/O in Ruby |
| Web URL | `/data/chart.png` | Links and images in HTML shown in the browser |
| Path in prompts and tool arguments | `report.pdf`, `projects/report.pdf` | What the model reads and writes; relative to the shared folder |

Paths come from `Monadic::Utils::Environment` (see [docs/environment_module.md](docs/environment_module.md)). Do not hard-code `/monadic/data` or `~/monadic/data`.

## Checking a Path from a Tool

`Monadic::Utils::SharedPathGuard` (`lib/monadic/utils/shared_path_guard.rb`):

- `resolve_in_shared(name, extensions: nil, must_exist: true)` returns the canonical path inside the shared folder, or nil. `resolve_in_shared!` raises `SharedPathGuard::InvalidPath` with a message that contains no path.
  - `name` may be relative, absolute, or start with `/monadic/data` (mapped to the shared folder in both modes).
  - Rejected: empty names, NUL, backslashes, `..` segments, a path whose real location (links followed) is outside the shared folder, a missing file when `must_exist`, and an extension not in `extensions`.
  - Subfolders are allowed.
- `command_path(path, container:)` returns the path to pass to a command: the host or container path for Ruby, the `/monadic/data/…` path for `container: "python"`.
- Every write in the shared folder goes through the guard, because code in the Python container can change the shared folder and put links in it while the server works:
  - `write_file!(path, content = nil, mode: "w", perm: nil, replace: true, sync_dir: false)` writes a new file under a temporary name and puts it in place (`replace: false` only when nothing has the name; `mode: "a"` appends to a plain file with one name); with a block and no content, the block writes. A link or a folder at the name is refused; an existing file keeps its permissions unless `perm` is given (set on the open file, never on a path).
  - `copy_file!`, `read_file!` (a plain file, never a link, a FIFO or a device), `file_stat`, `delete_file!` (a file or a link itself, never a folder), `mkdir_p!`, `make_dir!` (a new folder, with subfolders), `rename_file!` (plain files only) and `remove_tree!`.
  - None of them works in, or on, `apps`, `helpers`, `scripts` or `services`, by name (any case) or where they really are.
  - Underneath, `Monadic::Utils::SharedFs` opens the shared folder and each folder below it without following a link (`O_NOFOLLOW`, close-on-exec), and creates, renames and removes relative to the folder it holds open (`openat`, `renameat`, `linkat`, `unlinkat`, `mkdirat` through Fiddle). A folder swapped for a link meanwhile changes nothing; what the shared folder holds can still be changed afterwards, so its contents are not trusted.
  - An external program (ImageMagick, `patch`) is given a copy in the system's temporary folder, and its result is written back through the guard.
  - `scripts/lint/check_shared_writes.rb` fails on a raw write (`File.write`, `FileUtils.mkdir_p`, `Tempfile` in a folder, ...) outside `scripts/lint/shared_writes.allow`, which says for each one where it writes (state, logs, config, the system's temporary folder, the root of the shared folder) and why. `File.open` calls are found by parsing each file with Prism, so a path argument with its own parentheses or a call over several lines is read whole; a call counts as a write when its mode is a writing string, includes a `File::` write flag, or is a variable or other expression the lint cannot read.

`MonadicHelper#validate_file_path(file_path)` is `resolve_in_shared(file_path, must_exist: false)`: it returns the path or nil. Use the returned path for the operation, not the argument.

## Serving Files to the Browser

`GET /data/:file_name` and `GET /monadic/data/:file_name` (`lib/monadic/routes/static_routes.rb`) serve files through `Monadic::Utils::SharedFilePath.resolve`:

- only a file at the top of the shared folder; a name with `/` or `\`, `.` or `..` is refused;
- the real path (links followed) must stay inside the shared folder;
- otherwise the response is 404.

Responses carry `X-Content-Type-Options: nosniff`. HTML, XHTML, SVG and XML files also get a `Content-Security-Policy` sandbox, so their scripts run in an origin of their own.

A file the browser should show must therefore be written to the top of the shared folder.

## Tests

- `spec/unit/security/tool_paths_spec.rb`
- `spec/unit/security/shared_folder_writes_spec.rb`
- `spec/unit/security/code_files_spec.rb`
- `spec/unit/routes/static_routes_spec.rb`

## Related Documentation

- [docs/environment_module.md](docs/environment_module.md)
- `docs_dev/shared_folder_code_boundary.md`
