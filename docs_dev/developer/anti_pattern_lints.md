# Anti-Pattern Lints and Safe Helpers

The lint scripts in `scripts/lint/` run on every push in the `Lint` workflow (`.github/workflows/lint.yml`). Each one fails when a known class of defect appears. Several of them pair with a helper that is the allowed way to do the thing the lint forbids.

## Rules

Run a rule locally with `ruby scripts/lint/<script>.rb`, or through the rake task named below (`rake lint:<task>`).

| Script | Rake task | Fails when |
|---|---|---|
| `check_personal_paths.rb` | `lint:personal_paths` | A string literal contains a personal home path (`/Users/<name>/`, `/home/<name>/`, `C:\Users\<name>\`) in `app/` or the source folders of `docker/services/` (the Ruby `lib`, `scripts` and `public/js`, the Python scripts, and the extractor, embeddings and privacy services). Tests are excluded |
| `check_shell_escape.rb` | `lint:shell_escape` | A shell string (`docker exec`, `bash -c`, `system("...")`) interpolates a value that is not escaped or known to be safe |
| `check_xhr_pair.rb` | `lint:xhr_pair` | A route that depends on `request.xhr?` is called by a `fetch()` that does not send `X-Requested-With`, or the reverse |
| `check_data_path_literals.rb` | `lint:data_path_literals` | `"/monadic/data"` is written outside the `Environment` helper and the allow-listed files |
| `check_bare_ws_send.rb` | `lint:bare_ws_send` | `ws.send(...)` is called outside `monadic-ws.js` |
| `check_global_shadow_delegation.rb` | `lint:global_shadow_delegation` | A top-level function or variable in a classic script wraps the `window` global of the same name (the wrapper replaces the global and calls itself) |
| `check_http_timeout.rb` | `lint:http_timeout` | An outbound `http` gem call has no timeout (the gem has no default) |

The workflow also runs the documentation, translation, model and tracked-path checks in the same folder (`check_docs_parity.rb`, `check_docs_links.rb`, `check_duplicate_translation_keys.rb`, `check_app_docs_sync.rb`, `check_deprecated_models.rb`, `check_model_consistency.rb`, `check_api_key_urls.rb`, `check_tracked_paths.rb`) and the self-test of the lints (`scripts/lint/spec/check_self_test.rb`). The code lints (the rules above, the docs checks and `check_api_key_urls.rb`) report how many files they scanned and fail when the count is below a floor (most through `scripts/lint/scan_floor.rb`), so a lint that silently scans nothing does not pass.

## Helpers

### `Monadic::Shell` (Ruby)

`lib/monadic/shell.rb` is the helper for calling the docker CLI from Ruby code.

- Container names are symbols resolved through `CONTAINERS`.
- `exec(container:, argv:, workdir:, env:, timeout:)` runs a program with an argument array. No shell is involved, so nothing needs escaping.
- `bash(container:, body:, ...)` runs a shell body. Values spliced into the body must go through `Monadic::Shell.escape`.
- `cp_to_container` and `cp_from_container` copy files.

Use it instead of building `docker exec` strings; `lint:shell_escape` catches the string form.

### `monadicFetch` (JavaScript)

`public/js/monadic/monadic-fetch.js` wraps `fetch()`:

```js
const data = await monadicFetch.postJson('/document', formData);
const status = await monadicFetch.getJson('/api/status');
```

It always sends `X-Requested-With: XMLHttpRequest`. A response with a JSON content type is parsed, and a body that is not valid JSON throws an error with `status` and `body`. Any other response body is returned as a string. A non-success HTTP status throws an error whose message is the server's `error` field when it gives one. `lint:xhr_pair` checks the other side of this contract.

### JSON routes (Ruby)

Routes called from the web UI always return JSON (`content_type :json`) and have no non-JSON branch, so a request that misses a header cannot fall into an HTML or redirect response. `/load` and `/document` are examples.

### `safeWsSend` (JavaScript)

Every WebSocket message goes through `window.safeWsSend`; see [Safe WebSocket Send](../frontend/safe_ws_send.md). `lint:bare_ws_send` catches direct `ws.send` calls.
