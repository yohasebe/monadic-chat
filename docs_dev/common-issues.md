# Common Development Issues & Solutions

## Build Issues

### Electron packaging fails
```bash
# Clear npm cache
npm cache clean --force
rm -rf node_modules package-lock.json
npm install

# For notarization on Mac: a keychain profile saved with
# `xcrun notarytool store-credentials`
export NOTARY_PROFILE="notary"
```

### Docker build errors
```bash
# Complete cleanup (WARNING: removes unused images)
docker system prune -a --volumes

# Rebuild via compose
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## Runtime Issues

### "Cannot find module" errors after reorganization
- Check `app.isPackaged` conditionals in app/main.js
- Verify paths in process.resourcesPath vs __dirname

### API tests failing with provider-specific errors
- Prefer mdsl/model_spec defaults. Avoid forcing params (e.g., temperature) that a model may not support.
- Scope providers explicitly when isolating issues:
```bash
# Run only selected providers
RUN_API=true PROVIDERS=openai,anthropic rake "test:run[api]"

# Exclude local backends (e.g., Ollama) by omission
RUN_API=true PROVIDERS=openai,gemini rake "test:run[api]"
```
- Enable request logging to diagnose:
```bash
API_LOG=true RUN_API=true rake "test:run[api]"
```

### `file_importer_spec.rb` PDF extractor dispatch fails locally

`docker/services/ruby/spec/unit/library/file_importer_spec.rb` — the example "invokes the python
extractor and dispatches to PdfImporter" — can fail on a developer machine
while passing in CI.

- **Cause**: the example expects the PDF import to fall through to
  `run_python_extractor`. That path is taken only when the extractor
  (Knowledge Base Quality Pack) service is unavailable. In CI no extractor
  container is running, so the example passes. On a local dev box where the
  extractor container *is* up, `build_conversation` routes through the
  extractor service (`extract_via_service`) instead, and the container cannot
  read the host-side temp file the spec writes — the request 404s and the
  `have_received(:run_python_extractor)` assertion does not match.
- This example fails locally whenever the extractor container is running; CI
  runs without it.
- **Action**: none required for release. If you want a clean local run, stop
  the extractor container first, or run the suite in an environment matching
  CI. Do not "fix" it by mutating the assertion — the spec is correct for the
  CI environment it gates.

### WebSocket connection issues
1. Check Ruby server is running: `ps aux | grep falcon`
2. Verify port 4567 is accessible: `curl -fsS localhost:4567/`
3. Check browser console for CORS errors
4. Restart server: `rake server:restart`

### SSL errors: `certificate verify failed (unable to get certificate CRL)`

**Symptoms**
- `SSL_connect returned=1 ... unable to get certificate CRL` errors appear during `rake server:debug` or chat API calls, causing initialization or API call failures
- Occurs simultaneously across multiple providers (Gemini, Grok, DeepSeek, Cohere, etc.), preventing model list retrieval and halting DSL loading

**Root cause**
- OpenSSL's default verification fails when CRL (Certificate Revocation List) check certificates are missing in local environments like macOS

**Mechanism**
- `docker/services/ruby/lib/monadic/utils/ssl_configuration.rb` removes `V_FLAG_CRL_CHECK` and `V_FLAG_CRL_CHECK_ALL` from `OpenSSL::SSL::SSLContext::DEFAULT_PARAMS` at startup
- The same `SSLContext` is set on the `HTTP` gem's `default_options`, so every `http` gem request uses it
- Custom CAs can be prioritized by setting `SSL_CERT_FILE` / `SSL_CERT_DIR` in `~/monadic/config/env`
- `HTTP.headers` and `Net::HTTP.start` calls use this configuration

**Operational notes**
- `Monadic::Utils::ProviderModelCache` is the failsafe: when `helper.list_models` fails, falls back to default models and continues DSL loading. Detectable via `[ProviderModelCache] ... fallback` logs when `EXTRA_LOGGING=true`
- For operations without fallback, adjust `ProviderModelCache.fetch` usage locations and explicitly `clear(:provider)` to re-fetch
- New HTTP clients must use `SSLConfiguration.configure!`

### LaTeX-dependent apps (Concept Visualizer / Syntax Tree)
- These tools require Python service built with `INSTALL_LATEX=true`. MDSL's `disabled` condition is only lifted when pdflatex + dvisvgm (and necessary fonts) are available
- No need to re-check LaTeX toolchain availability at runtime or add fallbacks. Rebuild Docker image if environment is insufficient
- When assembling shell scripts on Ruby side, finalize flags like `needs_cjk` in Ruby before embedding in strings. Expanding uninitialized variables causes `bash: needs_cjk: unbound variable` errors

### ABC or Mermaid blocks corrupted in rendered messages

**Symptoms**: an ABC or Mermaid block shows table syntax (`|---|---|`), curly quotes, em-dashes or extra blank lines.

**Where rendering happens**: the server does not convert messages to HTML. `html_handler.rb` takes `<div class="abc-code">` blocks out of the text and puts them back unchanged, so the text reaches the browser as written. The browser's `MarkdownRenderer.render` (`public/js/monadic/markdown-renderer.js`) renders it with markdown-it (`typographer: true`).

**How blocks are protected**: before markdown-it runs, `render` replaces math and the fenced `abc` and `mermaid` code blocks with placeholders (`ABC_BLOCK_PLACEHOLDER_<n>`, `MERMAID_BLOCK_PLACEHOLDER_<n>`, …). Afterwards it puts the escaped content back (`<div class="abc-code"><pre>…</pre></div>` for ABC). A block type that is not protected this way goes through markdown-it and its typographer.

**Checks**:
- Make sure the block is a fenced code block whose opening fence is followed directly by `abc` or `mermaid` and a line break; that is the only form the renderer matches.
- To add a block type that must stay untouched, add a placeholder step to `render` in the same way.

### Passing multiline data to Node.js validation scripts

**Problem**: Multiline code (ABC notation, Mermaid diagrams, etc.) fails validation when passed as command-line arguments to Node.js scripts.

**Symptoms**:
- `process.argv[2]` is `undefined`
- Error: `Cannot read properties of undefined (reading 'split')`
- Validation fails randomly with complex input
- Multiple function calls triggered due to validation failures

**Root Cause**: Shell escaping of multiline strings with special characters is unreliable, causing arguments to be split or lost.

**Solution - Use stdin instead of command-line arguments**:

❌ **WRONG** (command-line args):
```ruby
# Unreliable with multiline/special chars
command = "node -e '#{validator_js}' #{Shellwords.escape(code)}"
stdout, stderr, status = Open3.capture3(command)
```

✅ **CORRECT** (stdin):
```ruby
# Reliable for any content
validator_js = self.class.abc_validator_js(abcjs_path)
stdout, stderr, status = Open3.capture3('node', '-e', validator_js, stdin_data: code)
```

**JavaScript side**:
```javascript
// Read from stdin instead of process.argv
const code = require('fs').readFileSync(0, 'utf-8');
```

**Benefits**:
- Works with any content length
- No escaping issues
- Handles special characters correctly
- Works across both container and host environments

**Related Issues**: Mermaid Grapher validation

## Development Tips

### Fast iteration on Ruby code
```bash
# Use debug mode to skip Ruby container
rake server:debug

# Watch logs
tail -f ~/monadic/log/server.log
```

### Testing specific providers
```bash
# Test only specific providers
RUN_API=true PROVIDERS=openai,anthropic rake "test:run[api]"

# Skip media tests for speed
RUN_API=true RUN_MEDIA=false rake "test:run[api]"
```

### Debugging Electron paths
```javascript
// Add to app/main.js temporarily
console.log('isPackaged:', app.isPackaged);
console.log('resourcesPath:', process.resourcesPath);
console.log('__dirname:', __dirname);
console.log('computed path:', computedPath);
```

## Performance Issues

### Slow container startup
- Increase Docker memory allocation (Docker Desktop → Settings)
- Use `rake server:debug` for development
- Optional services are compose profiles: turn off the Privacy container with `PRIVACY_FILTER=false` and the Knowledge Base Quality Pack with `EXTRACTOR_SERVICE=false`

### Startup shows "Refreshing Ruby control‑plane" too often
- What happens:
  - On Start, the app probes Ruby control‑plane health. If it is only in `starting` state, rebuilding is not necessary and just waiting is sufficient.
- Current behavior:
  - The app waits based on `START_HEALTH_TRIES`/`START_HEALTH_INTERVAL` and rebuilds Ruby only when health is explicitly `unhealthy`.
- How to tune:
  - Extend wait window to accommodate slower machines:
    ```
    START_HEALTH_TRIES=30
    START_HEALTH_INTERVAL=2
    ```
  - Disable auto‑refresh entirely (you will need to rebuild manually from the menu if truly broken):
    ```
    AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=false
    ```

### Test suite taking too long
```bash
# Run quick smoke tests only
RUN_API=true rake "test:run[api]"

# Use SUMMARY_ONLY for cleaner output
SUMMARY_ONLY=1 rake "test:run[api]"
```
