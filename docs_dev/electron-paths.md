# Electron: Dev vs Production Paths

Monadic Chat uses `app.isPackaged` to branch paths for scripts, icons, preload, and static assets.

Common patterns (see `app/main.js`):
- Icons directory:
  - Packaged: `path.join(process.resourcesPath, 'icons')`
  - Dev: `path.join(__dirname, 'icons')`
- Preload script:
  - Packaged: `path.join(process.resourcesPath, 'preload.js')`
  - Dev: `path.join(__dirname, 'preload.js')`
- Monadic shell scripts and static files follow the same pattern.

Tips:
- Use `app.isPackaged` (not `path.isPackaged`).
- Prefer absolute paths derived from `process.resourcesPath` in production.
- Avoid `__dirname` in code that runs after packaging unless guarded by `app.isPackaged`.
- Quote paths when invoking shell commands and consider platform differences.
- When running `electron .`, make sure relative paths resolve from `app/` correctly.

Debugging path issues:
- Add temporary logging around computed paths in `app/main.js`.
- Validate `preload.js` resolution by opening DevTools and checking if the preload API is available.
