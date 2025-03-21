# Monadic Chat Rake Tasks

Monadic Chat provides a set of Rake tasks to simplify development and management. These are wrappers around the `monadic_dev` commands.

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

## Testing & Linting

```bash
# Run specs
rake spec

# Run RuboCop
rake rubocop
rake rubocop:autocorrect
rake rubocop:autocorrect_all
```

## Build

```bash
# Build application packages
rake build
```