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
- `write_file!(path, content, mode: "w")` writes inside the shared folder, never through a link, and never into `apps`, `helpers`, `scripts` or `services` (`tool_writable?`).

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
