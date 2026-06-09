# Server Debug Mode

## Overview

`rake server:debug` starts the Monadic server in a non-daemonized debug mode using the local Ruby environment, while other containers (Python, pgvector, Selenium, etc.) are started and reused as needed.

This mode enables:
- **Extra logging** for debugging provider requests/responses
- **Local documentation access** for both internal and external docs
- **Direct Ruby execution** without container overhead
- **Single worker mode** (`--count 1`) for simplified debugging
- **Automatic process cleanup** of existing server instances on port 4567

## Quick Start

```bash
# Start server in debug mode
rake server:debug

# Access the application
open http://localhost:4567/

# Access documentation (in debug mode only)
open http://localhost:4567/docs/          # External docs
open http://localhost:4567/docs_dev/      # Internal docs
```

## Features

### Automatic Configuration

When you run `rake server:debug`, the following is automatically configured:

1. **`EXTRA_LOGGING=true`** - Enables detailed provider/debug logging
2. **`DEBUG_MODE=true`** - Enables local documentation serving
3. **Config loading** - Loads `~/monadic/config/env` for API keys

Example output:
```
Starting Monadic server in debug mode...
Extra logging: enabled (forced in debug mode)
Debug mode: enabled (local documentation available)
```

### Frontend JS (no bundle rebuild needed)

In debug mode the server runs on the host (`in_container?` is false), and the page loads the **raw JS source files directly**, in bundle order, instead of the prebuilt `monadic.bundle.min.js`. Editing any `public/js/**` file and reloading the browser reflects the change immediately — **no `npm run build:js` step is required in dev**. (The single minified bundle is a production-only artifact, loaded only when Ruby runs inside the container.)

The file list and order come from the same SSOT the bundler uses (`FILES` in `scripts/build_js_bundle.mjs`), parsed in `static_routes.rb` into `@dev_js_files`; if that parse ever fails the page falls back to the bundle.

### The Ruby container is stopped automatically

`rake server:debug` stops `monadic-chat-ruby-container` so the host Falcon owns port 4567 — you do **not** need to stop it manually. Be aware of one gotcha: if the container is running alongside the host server, its published `127.0.0.1:4567` can shadow the host's `*:4567` for `localhost` connections (macOS prefers the more specific bind), silently serving the container's baked-in code instead of your local edits. The dev start flow re-stops the container (including the case where the `MONADIC_DEV` recreate step brought it back up) before launching Falcon. If you suspect stale code is being served, check for both listeners:

```bash
lsof -nP -iTCP:4567 -sTCP:LISTEN   # a host `ruby` (*:4567) + a docker proxy (127.0.0.1:4567) means the container is shadowing
```

### Local Documentation Access

In debug mode, both internal and external documentation are served locally:

**Web UI Integration:**
- In debug mode, the web UI shows **local documentation links**
- In normal mode, the web UI shows **GitHub Pages links**

**Available documentation:**
- **External docs** (`/docs/`) - User-facing documentation
- **Internal docs** (`/docs_dev/`) - Developer documentation

### Benefits

- **No container overhead** - Ruby runs directly on your machine
- **Fast iteration** - Changes to Ruby code reflect immediately (no static file caching)
- **Rich logging** - See full provider requests/responses
- **Local docs** - Preview documentation changes without pushing to GitHub
- **Single worker** - Simplified WebSocket session routing for debugging
- **Clean startup** - Automatic cleanup of stale server processes

## When to Use

### Use `rake server:debug` when:
- Iterating on the Ruby service (`docker/services/ruby`) code
- Inspecting provider requests/responses with Extra Logging
- Editing documentation and want to preview changes locally
- Debugging application behavior with detailed logs

### Use `rake server:start` when:
- Running in production-like environment
- Testing full Docker container setup
- Don't need detailed logging
- Running as a background daemon

## Technical Details

### Route Configuration

Documentation routes are only active when `DEBUG_MODE=true`:

```ruby
# monadic.rb
get "/docs_dev/?*" do
  unless CONFIG["DEBUG_MODE"]
    status 404
    return "Documentation not available in production mode"
  end
  # ... serve files from docs_dev/
end
```

**Important:** `/docs_dev/?*` route must come **before** `/docs/?*` to prevent path matching conflicts.

### Path Resolution

Paths are resolved relative to `lib/monadic.rb` at runtime:

```ruby
# From docker/services/ruby/lib/monadic.rb to docs_dev/
docs_dev_root = File.expand_path("../../../../../docs_dev", __FILE__)

# From docker/services/ruby/lib/monadic.rb to docs/
docs_root = File.expand_path("../../../../../docs", __FILE__)
```

This approach ensures platform independence - no hardcoded paths.

### Security Features

1. **Path Traversal Protection** - Strips `..` from requested paths
2. **Directory Boundary Enforcement** - Verifies files are within allowed directories
3. **Production Protection** - Returns 404 when DEBUG_MODE is disabled

## Configuration

### Rakefile

```ruby
desc "Start the Monadic server in debug mode (non-daemonized)"
task :debug do
  # Force EXTRA_LOGGING to true in debug mode
  ENV['EXTRA_LOGGING'] = 'true'

  # Enable DEBUG_MODE for local documentation
  ENV['DEBUG_MODE'] = 'true'

  # Load configuration
  config_path = File.expand_path("~/monadic/config/env")
  Dotenv.load(config_path) if File.exist?(config_path)

  # Start server
  sh "./bin/monadic_server.sh debug"
end
```

### monadic.rb

```ruby
# Initialize CONFIG with default values
CONFIG = {
  "EXTRA_LOGGING" => ENV["EXTRA_LOGGING"] == "true" || false,
  "DEBUG_MODE" => ENV["DEBUG_MODE"] == "true" || false,
  # ...
}

# Override with environment variables
if ENV["DEBUG_MODE"]
  CONFIG["DEBUG_MODE"] = ENV["DEBUG_MODE"] == "true"
end
```

### index.erb

Conditional UI rendering:

```erb
<% if @debug_mode %>
  <!-- Show local documentation links -->
  <a href="/docs/">Docs</a> <small style="color: #28a745;">(local)</small>
  <a href="/docs_dev/">Docs Dev</a> <small style="color: #dc3545;">(internal)</small>
<% else %>
  <!-- Show GitHub Pages link -->
  <a href="https://yohasebe.github.io/monadic-chat/">Homepage</a>
<% end %>
```

## Troubleshooting

### Documentation Returns 404

**Symptom:** Clicking docs links shows "File not found"

**Solution:**
1. Verify debug mode is enabled:
   ```bash
   rake server:debug
   # Should show: "Debug mode: enabled (local documentation available)"
   ```

2. Check files exist:
   ```bash
   ls docs_dev/index.html
   ls docs/index.html
   ```

3. Check logs with `EXTRA_LOGGING`:
   ```
   [DEBUG_MODE] Docs_dev request: requested_path='', docs_dev_root='/path/to/docs_dev'
   [DEBUG_MODE] Trying to serve: /path/to/docs_dev/index.html
   ```

### Server Won't Start

**Common causes:**
- Port 4567 already in use
- Missing dependencies (`bundle install`)
- Docker containers not running

**Solution:**
```bash
# Check port
lsof -i :4567

# Install dependencies
bundle install

# Ensure Docker is running
docker ps
```

## Related Tasks

- `rake server:start` - Daemonized mode via `./bin/monadic_server.sh start`
- `rake server:stop` - Stop the locally running server
- `rake server:restart` - Restart the server
- `rake spec` - Run tests

## Platform Support

Works on all Unix-like systems:
- ✅ macOS (Darwin)
- ✅ Linux (Ubuntu, Debian, CentOS, etc.)
- ✅ BSD (FreeBSD, etc.)

## See Also

- [Logging](logging.md) - Debug logging configuration
- [Common Issues](common-issues.md) - General troubleshooting
- [Docker Architecture](docker-architecture.md) - Server architecture overview
- [README](README.md) - Documentation structure
