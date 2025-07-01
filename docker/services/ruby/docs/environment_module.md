# Environment Module Summary

## Overview
Container detection and path resolution are handled by `Monadic::Utils::Environment` module.

## Key Features
- **Container Detection**: `in_container?` method
- **Path Resolution**: Automatic path adjustment for container vs local execution  
- **PostgreSQL Configuration**: `postgres_params` method with correct host/port

## Usage
```ruby
# Check environment
if Monadic::Utils::Environment.in_container?
  # Container-specific logic
end

# Get database connection
conn = PG.connect(Monadic::Utils::Environment.postgres_params)

# Get paths
data_path = Monadic::Utils::Environment.data_path
scripts_path = Monadic::Utils::Environment.scripts_path
plugins_path = Monadic::Utils::Environment.plugins_path
```

## Available Methods
- `in_container?` - Returns true if running inside Docker container
- `data_path` - Returns correct data directory path
- `scripts_path` - Returns correct scripts directory path  
- `plugins_path` - Returns correct plugins directory path
- `postgres_params(database: nil)` - Returns PostgreSQL connection parameters