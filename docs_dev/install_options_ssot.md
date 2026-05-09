# Install Options — Single Source of Truth (SSOT)

This page is the canonical reference for *adding*, *renaming*, or
*removing* install options that the Settings → Install Options panel
exposes. Every install option (Python build flag, Privacy Filter
language, Extractor OCR language) is configured by editing **one
config file plus a small, well-known set of integration sites**
listed at the bottom.

## Why this exists

Before beta.16 the option list was duplicated across 6+ files and
~22 sites. Adding a new `PYOPT_X` checkbox required editing a
hand-maintained array in each of `app/main.js`, `app/settings.html`,
`docker/monadic.sh`, `docker/services/python/compose.yml`,
`docker/services/python/Dockerfile`, and 7 translation files — and
every refactor had to remember each one or risk silent drift (a
checkbox the user could toggle but the build script ignored).

## The SSOT file

```
app/install_options.config.js
```

This CommonJS module is the source of truth for:

| What | Exported field |
| --- | --- |
| Python build options (PYOPT_* / INSTALL_* / IMGOPT_*) | `PYTHON_OPTIONS` (array of `{ id, env, label, group }`) |
| Env-key list for Python rebuild detection | `ENV_KEYS_PYTHON` |
| Privacy Filter languages (always installed) | `PRIVACY_LANG_BASE` |
| Privacy Filter languages (opt-in) | `PRIVACY_LANG_OPTIONAL` |
| Privacy Filter languages (full) | `PRIVACY_LANG_ALL` |
| Extractor OCR languages (always installed) | `EXTRACTOR_LANG_BASE` |
| Extractor OCR languages (opt-in) | `EXTRACTOR_LANG_OPTIONAL` |
| Extractor OCR languages (full) | `EXTRACTOR_LANG_ALL` |

The module is plain CommonJS so it can be `require()`'d from
`app/main.js` *and* read by `docker/monadic.sh` via a one-line
`node -e ...` expression — no bundler step, no codegen.

## The integration sites

Editing `install_options.config.js` alone will not surface a new
option to users; the option also has to be wired through the
build pipeline (which is intentionally not auto-generated, since
Dockerfile cache keys depend on stable ARG names). The integration
sites are:

| Site | Role | Lookup |
| --- | --- | --- |
| `app/install_options.config.js` | The SSOT | — |
| `app/main.js` | Reads `installOptions.ENV_KEYS_PYTHON` for rebuild diff + env normalization | `require('./install_options.config')` |
| `app/settings.html` | HTML checkbox + the `pyKeys` lookup table that powers the in-sync / rebuild-needed badge | hand-authored to keep `data-i18n` declarative |
| `docker/monadic.sh` | The `PY_OPTIONS=(...)` array drives read / compare / build_arg / save in a single loop | hand-authored (bash) |
| `docker/services/python/Dockerfile` | `ARG PYOPT_X=false` declaration + `RUN if [ "$PYOPT_X" = "true" ]` block | hand-authored (build-time) |
| `docker/services/python/compose.yml` | `PYOPT_X: ${PYOPT_X:-false}` ARG passthrough | hand-authored (compose) |
| `docker/services/ruby/public/js/i18n/translations.js` | Localized labels for the checkbox row | hand-authored (i18n) |

## Adding a new Python install option (checklist)

1. **`app/install_options.config.js`** — append a new entry to
   `PYTHON_OPTIONS`:
   ```js
   Object.freeze({ id: 'pyopt-foo', env: 'PYOPT_FOO', label: 'Foo (CPU)', group: 'python' }),
   ```
2. **`docker/services/python/Dockerfile`** — add an `ARG PYOPT_FOO=false`
   declaration and a `RUN if [ "$PYOPT_FOO" = "true" ]; then uv pip
   install --no-cache foo; ...; fi` block.
3. **`docker/services/python/compose.yml`** — add the ARG passthrough:
   ```yaml
   PYOPT_FOO: ${PYOPT_FOO:-false}
   ```
4. **`docker/monadic.sh`** — append `PYOPT_FOO` to the `PY_OPTIONS=( … )`
   array near the top of the python build function. The read /
   compare / build_arg / save loops pick it up automatically.
5. **`app/settings.html`** — add the checkbox row in the appropriate
   section (Python Libraries / Music Analysis / System Tools), the
   `pyKeys` lookup entry (`PYOPT_FOO: 'pyopt-foo'`), and the save /
   load handler entries.
6. **`docker/services/ruby/public/js/i18n/translations.js`** — add
   the localized label across all 7 languages if the label needs
   translation (most tool names stay in English).

## Removing an option

Inverse of adding: remove the entry from `install_options.config.js`,
the Dockerfile, the compose ARG, the bash array, the HTML row, and
the i18n strings. The 2026-05-09 PYOPT_SCIKIT removal (after
scikit-learn was promoted to default-installed) followed this exact
sequence — see the matching commit for a worked example.

## What is NOT covered by SSOT (intentional)

- **Dockerfile structure** (build-time ARG names, RUN conditional
  bodies) — the Dockerfile is the build-time contract. Auto-generating
  it would couple the SSOT to the cache-key invariants of `docker
  build` and is out of scope.
- **HTML markup** — the checkbox rows are hand-authored to keep
  `data-i18n` attributes declarative for the i18n tooling. Generating
  them at runtime would require either custom DOM templating or losing
  the static `data-i18n` discoverability.
- **i18n labels** — `translations.js` owns localization. The
  `label` field in `install_options.config.js` is the English
  fallback only.

## Related specs

- `spec/unit/dsl/openai_api_param_consistency_spec.rb` — spec-level
  invariant for OpenAI request bodies (parallel pattern: SSOT in
  `OpenAIHelper::OUTPUT_TOKEN_KEY`).
- `spec/unit/dsl/path_resolution_consistency_spec.rb` — spec-level
  invariant for shared-volume path resolution.
