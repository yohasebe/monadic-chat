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

### Document Database

```bash
# Export document database
rake db:export

# Import document database
rake db:import
```

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

**Note**: Help database tasks require the pgvector container to be running.

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
rake build:mac           # Both macOS packages
rake build:mac_arm64     # macOS arm64 (Apple Silicon)
rake build:mac_x64       # macOS x64 (Intel)
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

# Update assets in existing release
rake release:update_assets[version,file_patterns]
UPDATE_CHANGELOG=true rake release:update_assets[version,file_patterns]
```

## Notes

### Environment Variables

- `EXTRA_LOGGING=true` - Enable detailed logging (automatically set in debug mode)
- `DRYRUN=true` - Run version update in dry-run mode
- `DRAFT=true` - Create GitHub release as draft
- `UPDATE_CHANGELOG=true` - Update changelog when updating release assets

### Development Environment

When running outside Docker, the Rakefile automatically sets:
- `POSTGRES_HOST=localhost`
- `POSTGRES_PORT=5433` (to avoid conflicts with local PostgreSQL)

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
# Run all tests (Ruby + JavaScript) and code style checks
rake

# Run all Ruby tests (RSpec)
rake spec
rake test  # Alias

# Run specific test categories
rake spec_unit        # Unit tests only (fast, no dependencies)
rake spec_integration # Integration tests (requires containers)
rake spec_system      # System tests (MDSL validation)
rake spec_docker      # Docker infrastructure tests
rake spec_e2e         # End-to-end tests (requires API keys)

# Code quality checks
rake rubocop          # Ruby code style
rake eslint           # JavaScript linting
rake jstest           # JavaScript tests (Jest)
```

### Test Dependencies

| Test Type | Required Dependencies |
|-----------|----------------------|
| `spec_unit` | Ruby only |
| `spec_integration` | • PostgreSQL + pgvector (Docker, port 5433)<br>• Python container (Flask API, port 5070)<br>• Selenium container (port 4444)<br>• OpenAI API key (for embeddings) |
| `spec_system` | Ruby only |
| `spec_docker` | All Docker containers running |
| `spec_e2e` | • All Docker containers<br>• AI provider API keys<br>• WebSocket server (auto-started) |

### E2E Testing

The `rake spec_e2e` task provides comprehensive end-to-end testing:

```bash
# Test all providers
rake spec_e2e

# Test specific workflows
rake spec_e2e:chat
rake spec_e2e:code_interpreter
rake spec_e2e:jupyter_notebook
rake spec_e2e:voice_chat

# Test specific provider
rake spec_e2e:code_interpreter_provider[openai]
rake spec_e2e:code_interpreter_provider[claude]
```

**Features**:
- Automatic container startup and health checks
- Provider coverage summary
- Custom retry mechanism for reliability
- Flexible validation for different AI response formats