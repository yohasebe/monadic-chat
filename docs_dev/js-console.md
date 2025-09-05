# JavaScript Console Log Modes (Developer)

Monadic Chat offers two primary places to observe logs during development:

- Electron DevTools Console — standard browser console in the Electron window.
- Console Panel (app console) — the in-app console described in `docs/basic-usage/console-panel.md`.

## Electron DevTools

- Open with `Cmd/Ctrl+Shift+I` in the Electron window.
- Network/API details appear when Extra Logging is enabled (see Logging Guide).
- In `app/main.js`, Electron runtime logging flags are defaulted to disabled for production noise control:
  - `process.env.ELECTRON_ENABLE_LOGGING = '0'`
  - `process.env.ELECTRON_DEBUG_EXCEPTION_LOGGING = '0'`
  You can temporarily enable these for deep debugging by setting them to `'1'` before running `electron .`.

## App Console Panel

- Refer to `docs/basic-usage/console-panel.md` for user-level operations.
- As a developer, you can watch startup, container orchestration, and server logs here while developing.
- Menu → Open → Open Log Folder jumps to `~/monadic/log` (see Logging Guide).

## Granular Debug Categories

- Unified debug categories can be controlled via `~/monadic/config/env`:
  - `MONADIC_DEBUG=api,embeddings` (comma-separated)
  - `MONADIC_DEBUG_LEVEL=debug` (none, error, warning, info, debug, verbose)
- In debug runs (`rake server:debug`), `EXTRA_LOGGING` is forced to true.
