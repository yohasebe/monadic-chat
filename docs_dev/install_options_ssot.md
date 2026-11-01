# Install Options

This page lists where the options of **Actions → Install Options** are defined: the optional Python layers, the Privacy Filter languages and the Extractor OCR languages.

## `app/install_options.config.js`

A CommonJS module required by `app/main.js`. It exports:

| Export | Content |
|---|---|
| `PYTHON_OPTIONS` | Python build options, each `{ id, env, label, group }`: `id` is the checkbox id in `settings.html`, `env` the variable in `~/monadic/config/env` and the Dockerfile `ARG`, `label` the English fallback, `group` one of `python`, `system`, `music`, `tools` |
| `ENV_KEYS_PYTHON` | The `env` names of `PYTHON_OPTIONS`, used by `main.js` for rebuild detection and env normalization |
| `PRIVACY_LANG_BASE` / `PRIVACY_LANG_OPTIONAL` / `PRIVACY_LANG_ALL` | Privacy Filter languages. `en` is always on; the others are opt-in |
| `EXTRACTOR_LANG_BASE` / `EXTRACTOR_LANG_OPTIONAL` / `EXTRACTOR_LANG_ALL` | Extractor OCR languages. `en` is always on; the others are opt-in |

The language selections are runtime settings: compose passes them to the containers as `PRIVACY_LANGS_RUNTIME` and `EXTRACTOR_LANGS_RUNTIME`, and the images do not depend on them.

## Sites for a Python Option

| File | What it holds |
|---|---|
| `app/install_options.config.js` | The `PYTHON_OPTIONS` entry |
| `app/settings.html` | The checkbox row, the `pyKeys` table (in-sync / rebuild-needed badge) and the save and load entries |
| `docker/monadic.sh` | `PY_OPTIONS=( … )`; the read, compare, build-arg and save loops use it |
| `docker/services/python/Dockerfile` | `ARG PYOPT_X=false` and `RUN if [ "$PYOPT_X" = "true" ] …` |
| `docker/services/python/compose.yml` | `PYOPT_X: ${PYOPT_X:-false}` under build args |
| `docker/services/ruby/public/js/i18n/translations.js` | The label in the 7 UI languages, when it is translated |

## Adding a Python Option

1. Append to `PYTHON_OPTIONS`:
   ```js
   Object.freeze({ id: 'pyopt-foo', env: 'PYOPT_FOO', label: 'Foo (CPU)', group: 'python' }),
   ```
2. In the Dockerfile, add `ARG PYOPT_FOO=false` and a `RUN if [ "$PYOPT_FOO" = "true" ]; then uv pip install --no-cache foo; …; fi` layer.
3. In `compose.yml`, add `PYOPT_FOO: ${PYOPT_FOO:-false}`.
4. In `monadic.sh`, append `PYOPT_FOO` to `PY_OPTIONS`.
5. In `settings.html`, add the checkbox row in its section, the `pyKeys` entry (`PYOPT_FOO: 'pyopt-foo'`) and the save and load entries.
6. Add translations if the label is translated.

Removing an option is the same list in reverse.

## Adding a Privacy Filter Language

Add it to the privacy service's `language_map.json` (which puts the model in the image), append it to `PRIVACY_LANG_OPTIONAL`, add the checkbox row in `settings.html` and the translations.
