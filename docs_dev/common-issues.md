# Common Development Issues & Solutions

## Build Issues

### Electron packaging fails
```bash
# Clear npm cache
npm cache clean --force
rm -rf node_modules package-lock.json
npm install

# For notarization issues on Mac
export APPLE_ID="your-apple-id"
export APPLE_APP_SPECIFIC_PASSWORD="your-app-password"
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
- Run `scripts/fix_packaged_paths.sh` if needed

### API tests failing with provider-specific errors
- Prefer mdsl/model_spec defaults. Avoid forcing params (e.g., temperature) that a model may not support.
- Scope providers explicitly when isolating issues:
```bash
# Run only selected providers
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# Exclude local backends (e.g., Ollama) by omission
RUN_API=true PROVIDERS=openai,gemini rake spec_api:all
```
- Enable request logging to diagnose:
```bash
API_LOG=true RUN_API=true rake spec_api:smoke
```

### WebSocket connection issues
1. Check Ruby server is running: `ps aux | grep thin`
2. Verify port 4567 is accessible: `curl localhost:4567/health`
3. Check browser console for CORS errors
4. Restart server: `rake server:restart`

### SSL errors: `certificate verify failed (unable to get certificate CRL)`

**Symptoms**
- `SSL_connect returned=1 ... unable to get certificate CRL` errors appear during `rake server:debug` or chat API calls, causing initialization or API call failures
- Occurs simultaneously across multiple providers (Gemini, Grok, DeepSeek, Cohere, etc.), preventing model list retrieval and halting DSL loading

**Root cause**
- OpenSSL's default verification fails when CRL (Certificate Revocation List) check certificates are missing in local environments like macOS

**Resolution (2024-03)**
- Added `docker/services/ruby/lib/monadic/utils/ssl_configuration.rb` to disable `V_FLAG_CRL_CHECK` and `V_FLAG_CRL_CHECK_ALL` from `OpenSSL::SSL::SSLContext::DEFAULT_PARAMS` at startup
- Applied same `SSLContext` to `HTTP` gem's `default_options` to unify across entire Ruby service
- Custom CAs can be prioritized by specifying `SSL_CERT_FILE` / `SSL_CERT_DIR` in `.env`
- Existing HTTP calls (`HTTP.headers`, `Net::HTTP.start`) share the new configuration without additional modifications

**Operational notes**
- Introduced `Monadic::Utils::ProviderModelCache` as failsafe: when `helper.list_models` fails, falls back to default models and continues DSL loading. Detectable via `[ProviderModelCache] ... fallback` logs when `EXTRA_LOGGING=true`
- For operations without fallback, adjust `ProviderModelCache.fetch` usage locations and explicitly `clear(:provider)` to re-fetch
- When introducing new HTTP clients in future, reuse `SSLConfiguration.configure!` to prevent CRL issues from recurring

### LaTeX-dependent apps (Concept Visualizer / Syntax Tree)
- These tools require Python service built with `INSTALL_LATEX=true`. MDSL's `disabled` condition is only lifted when pdflatex + dvisvgm (and necessary fonts) are available
- No need to re-check LaTeX toolchain availability at runtime or add fallbacks. Rebuild Docker image if environment is insufficient
- When assembling shell scripts on Ruby side, finalize flags like `needs_cjk` in Ruby before embedding in strings. Expanding uninitialized variables causes `bash: needs_cjk: unbound variable` errors

### HTML content being corrupted by Markdown processing

**Problem**: Special HTML blocks (e.g., ABC notation, custom widgets) are being corrupted when processed through the Markdown converter with `smart: true` option.

**Symptoms**:
- ABC music notation blocks showing markdown table syntax (`|---|---|`)
- Curly quotes replacing straight quotes in HTML attributes
- Em-dashes appearing in place of hyphens
- Blank lines being inserted unexpectedly

**Root Cause**: HTML blocks are being passed through `markdown_to_html()` which applies smart typography transformations.

**Solution - Placeholder Pattern** (`docker/services/ruby/lib/monadic/utils/websocket.rb:1384-1402`):
```ruby
# 1. Extract special HTML blocks BEFORE markdown processing
abc_blocks = []
text_for_markdown = text.gsub(/<div class="abc-code">.*?<\/div>/m) do |match|
  abc_blocks << match
  "\n\nABC_PLACEHOLDER_#{abc_blocks.size - 1}\n\n"
end

# 2. Process markdown on the sanitized text
html = markdown_to_html(text_for_markdown, mathjax: mathjax_enabled)

# 3. Restore special blocks AFTER markdown processing
abc_blocks.each_with_index do |block, index|
  html.gsub!(/<p>\s*ABC_PLACEHOLDER_#{index}\s*<\/p>/, block)
  html.gsub!("ABC_PLACEHOLDER_#{index}", block)
end
```

**Key Principles**:
- Never process HTML through markdown converters
- Use placeholder pattern for content that must remain untouched
- Match the HTML structure exactly when replacing placeholders

**Related Issues**: Chord Accompanist ABC corruption (2024-01)

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

**Related Issues**: Chord Accompanist validation loops (2024-01), Mermaid Grapher validation

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
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# Skip media tests for speed
RUN_API=true RUN_MEDIA=false rake spec_api:all
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
- Disable unused containers in docker/compose.yml

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
RUN_API=true rake spec_api:quick

# Use SUMMARY_ONLY for cleaner output
SUMMARY_ONLY=1 rake spec_api:smoke
```
