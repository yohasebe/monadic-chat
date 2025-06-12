# Monadic Chat Rake Tasks for Developers

Monadic Chat provides a set of Rake tasks to simplify development and management. These are wrappers around the `monadic_server.sh` commands.

## Server Management

```bash
# Start the server in daemon mode
rake start
rake server:start

# Start the server in debug mode (foreground)
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

```bash
# Export document database
rake db:export

# Import document database
rake db:import

# Build help database (incremental)
rake help:build

# Rebuild help database from scratch
rake help:rebuild

# Export help database
rake help:export

# Show help database statistics
rake help:stats
```

## Asset Management

```bash
# Download vendor assets from CDN
rake download_vendor_assets
```

## Version Management

```bash
# Check version consistency
rake check_version

# Update version numbers
rake update_version[from_version,to_version]
```

## Build

```bash
# Build application packages
rake build
```

## Testing

```bash
# Run Ruby tests
rake spec

# Run JavaScript tests (passing tests only)
rake jstest

# Run all JavaScript tests
rake jstest_all

# Run all tests (Ruby and JavaScript)
rake test
```