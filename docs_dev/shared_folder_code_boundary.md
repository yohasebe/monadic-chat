# Shared Folder and Server Code

The shared folder (`~/monadic/data`, `/monadic/data` in the containers) is written by the tools that run code in the containers. Files there are data: the server runs or loads code from it only through the rules below. Keep to them when you add a tool, a route or a container.

## What the server runs and loads

- **Commands on the Ruby side** (`send_command(container: "ruby")`): only the scripts that come with Monadic Chat run, by their absolute path with `RbConfig.ruby`; a Ruby script that is not bundled is refused. PATH holds the bundled script folders and the server's own PATH without the shared folder. Credentials are removed from the command's environment; the bundled scripts read their keys from the configuration (`SecretReferences.config_value`). User scripts in the shared folder's `scripts` run only in the Python container.
- **Custom apps and helpers** (`apps/`, `helpers/`): loaded only through `SharedPathGuard.user_code_files` (which uses `code_files` and `code_file?`): no folder that is a link, no file that is a link, has another hard link, or lies outside its folder. The DSL loader loads an app's `_constants.rb` and `_tools.rb` under the same rule.
- **Container definitions** (`services/`, `apps/*/services/`): `monadic.sh` includes their `compose.yml` in `docker compose` runs and builds them with "Build User Containers". Generated compose files are written to `~/monadic/config`, never to the shared folder.
- **Files the Electron app writes or reads in the shared folder** (the Document DB export and import): through `app/no_follow_files.js`. Writes are made in `~/monadic/.staging` and renamed into place once written in full; reads open only the regular file that was checked. The app opens only the shared folder itself; any other entry is shown selected in the file manager.
- **The Python container's PATH:** the user's `scripts/` comes after the system's directories.

## Where the rules are kept

- **Mounts:** `apps/`, `helpers/` and `services/` are mounted read-only in every container that mounts the shared folder (Python, Selenium, Extractor and Ruby). `monadic.sh` (`ensure_code_dirs`) creates them as the user before any container starts, and does not start when one cannot be created or is a link (taking containers down still works). `test/electron/code-dirs-mount.test.js` checks the mounts in a real container on Linux in CI.
- **Writes by the server:** a write whose file name a model or a page chooses (file tools, uploads, web search saves, files a provider sends, app templates, AutoForge's project files) goes through `SharedPathGuard.write_file!`, which refuses the `apps`, `helpers`, `scripts` and `services` folders and a link in the file's place.
- **Tests:** a spec that makes a tool write into the shared folder points `Monadic::Utils::Environment.shared_volume` and `data_path` at a temporary folder; a spec that needs the user's shared folder (a running container reads it) removes what it put there.

## Development mode

With `rake server:debug` the server runs on the host and does not load custom apps or helpers from the shared folder unless it is started with `MONADIC_LOAD_USER_CODE=true` in the shell:

```bash
MONADIC_LOAD_USER_CODE=true rake server:debug
```

Only the shell turns it on: `rake server:debug` passes the setting to the server only when the shell had it, and the server ignores it when `~/monadic/config/env` mentions the name. When it is off and the folders hold files, the server says so once at startup. Set it only while you work on a custom app.
