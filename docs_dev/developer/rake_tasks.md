# Monadic Chat Rake Tasks for Developers

Monadic Chat provides a comprehensive set of Rake tasks to simplify development, testing, building, and release management.

## Default Task

```bash
# Run both spec and rubocop (default task)
rake
```

## Server Management

```bash
# Start the server in daemon mode
rake start
rake server:start

# Start the server in debug mode (foreground, EXTRA_LOGGING=true)
rake debug
rake server:debug

# Stop the server
rake stop
rake server:stop

# Restart the server
rake server:restart

# Display server and container status
rake status
rake server:status
```

## Database Operations

### Help Database

```bash
# Build help database (incremental)
rake help:build

# Rebuild help database from scratch
rake help:rebuild

# Export help database for distribution
rake help:export

# Show help database statistics
rake help:stats
```

**Note**: Help database tasks need the qdrant and embeddings containers. `rake help:build` starts the embeddings container itself if it is not already running.

## Asset Management

```bash
# Download vendor assets from CDN
rake download_vendor_assets
```

## Version Management

```bash
# Check version consistency across all files
rake check_version

# Update version numbers (automatically updates CHANGELOG.md)
rake update_version[to_version]
rake update_version[from_version,to_version]

# Dry run mode
DRYRUN=true rake update_version[to_version]
```

## Build Tasks

```bash
# Build all platform packages
rake build

# Platform-specific builds
rake build:win           # Windows x64
rake build:mac           # macOS (Apple Silicon only)
rake build:mac_arm64     # macOS arm64 (Apple Silicon)
rake build:linux         # Both Linux packages
rake build:linux_x64     # Linux x64
rake build:linux_arm64   # Linux arm64
```

## Release Management

**Note**: Requires GitHub CLI (`gh`) to be installed and authenticated.

```bash
# Create a new GitHub release
rake release:github[version,prerelease]

# Create a draft release
rake release:draft[version,prerelease]
DRAFT=true rake release:github[version,prerelease]

# List all releases
rake release:list

# Delete a release and its tag
rake release:delete[version]

# Update assets in existing release (adds a dated line to its release notes)
rake release:update_assets[version,file_patterns]
```

## Notes

### Environment Variables

- `EXTRA_LOGGING=true` - Enable detailed logging (automatically set in debug mode)
- `DRYRUN=true` - Run version update in dry-run mode
- `DRAFT=true` - Create GitHub release as draft

### Version Update

The `update_version` task updates version numbers in:
- `docker/services/ruby/lib/monadic/version.rb`
- `package.json` and `package-lock.json`
- `docker/monadic.sh`
- Documentation files
- `CHANGELOG.md` (adds new version section)

## Testing and Code Quality

For comprehensive testing documentation, see the [Testing Guide](testing_guide.md).

### Quick Test Commands

```bash
# Run all tests (Ruby, JavaScript and Python)
rake test

# Quick runs
rake spec:quick       # Ruby unit + integration
rake test:quick       # Ruby unit + integration, then Jest

# Ruby specs by directory (from docker/services/ruby)
bundle exec rspec spec/unit --tag '~integration' --tag '~e2e'
bundle exec rspec spec/integration
rake spec_e2e:jupyter_notebook  # E2E: Jupyter local ops
rake spec_e2e:monadic_context   # E2E: Monadic context display

# Code quality checks
rake rubocop          # Ruby code style
npx eslint .          # JavaScript linting
rake jstest           # JavaScript tests (Jest)
```

### Test Dependencies

| Test Type | Required Dependencies |
|-----------|----------------------|
| `spec/unit` | Ruby only |
| `spec/integration` | • Qdrant + embeddings containers (started automatically by `rake test`)<br>• Python container (Docker)<br>• Selenium container (port 4444) |
| `spec_e2e` | • All Docker containers<br>• AI provider API keys<br>• WebSocket server (auto-started) |

### E2E Testing

The `spec_e2e` Rake namespace provides end-to-end testing:

```bash
# Test specific workflows
rake spec_e2e:jupyter_notebook
rake spec_e2e:monadic_context
```

**Features**:
- Automatic container startup and health checks
- Provider coverage summary
- Custom retry mechanism for reliability
- Flexible validation for different AI response formats