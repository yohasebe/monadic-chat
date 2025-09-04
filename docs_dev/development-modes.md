# Development and Production Modes

## Overview

Monadic Chat can run in two distinct modes: Development Mode and Production Mode. Each mode has different characteristics and use cases.

## Development Mode

### How to Start
```bash
# From project root
rake server:debug
# or
rake debug
```

### Characteristics
- Ruby container is **stopped** to allow running the Ruby application directly on host
- Other containers (Python, PostgreSQL, Selenium, Ollama) continue running
- **EXTRA_LOGGING=true** is automatically set for detailed logging
- Server runs in foreground (not daemonized)
- Hot reload enabled for code changes
- Detailed error messages and stack traces
- All debug output visible in console

### Use Cases
- Developing new features
- Debugging application issues
- Testing MDSL files
- Monitoring real-time logs
- API testing and integration

### Environment
- Ruby application runs on host machine (port 4567)
- Direct access to source files for editing
- Immediate reflection of code changes
- Access to development tools and debuggers

## Production Mode

### How to Start

#### Via Electron App
```bash
# Build and run
electron .
```

#### Via Built Application
- Launch the installed Monadic Chat application
- Double-click the app icon (Mac/Windows/Linux)

#### Via Rake (daemon mode)
```bash
rake start
# or
rake server:start
```

### Characteristics
- All containers running including Ruby container
- Minimal logging (EXTRA_LOGGING=false by default)
- Server runs as daemon in background
- Optimized for performance
- Error messages are user-friendly
- Automatic restart on crashes

### Use Cases
- End-user deployment
- Production environments
- Stable operation
- Resource-efficient operation

### Environment
- All services containerized
- Isolated from host system
- Consistent environment across platforms
- Automatic container management

## Mode Detection

The system automatically detects the mode based on:

1. **Launch method**
   - `rake server:debug` → Development Mode
   - `electron .` → Production Mode
   - Built app → Production Mode

2. **Environment variables**
   ```ruby
   # In code
   if Monadic::Utils::Environment.in_container?
     # Production mode (containerized)
   else
     # Development mode (host)
   end
   ```

## Configuration Differences

### Logging

**Development Mode:**
```bash
EXTRA_LOGGING=true
MDSL_VALIDATION_VERBOSE=true
DEBUG=true
```

**Production Mode:**
```bash
EXTRA_LOGGING=false
MDSL_VALIDATION_VERBOSE=false
DEBUG=false
```

### Port Configuration

**Development Mode:**
- Ruby server: localhost:4567 (host)
- PostgreSQL: localhost:5433 (mapped from container)
- Python: localhost:5000 (container)

**Production Mode:**
- Ruby server: monadic-chat-ruby-container:4567
- PostgreSQL: pgvector_service:5432
- Python: python_service:5000

## Switching Between Modes

### From Production to Development
1. Stop the production server:
   ```bash
   rake stop
   ```
2. Start in development mode:
   ```bash
   rake server:debug
   ```

### From Development to Production
1. Stop the development server (Ctrl+C in console)
2. Start in production mode:
   ```bash
   rake start
   ```

## Container Management

### Development Mode Containers
```bash
# Check running containers (Ruby container should be absent)
docker ps | grep monadic-chat

# Expected output:
monadic-chat-python-container
monadic-chat-pgvector-container
monadic-chat-selenium-container
# Note: NO monadic-chat-ruby-container
```

### Production Mode Containers
```bash
# All containers should be running
docker ps | grep monadic-chat

# Expected output:
monadic-chat-ruby-container
monadic-chat-python-container
monadic-chat-pgvector-container
monadic-chat-selenium-container
monadic-chat-ollama-container  # if built
```

## Troubleshooting

### Development Mode Issues

**Ruby container is running:**
```bash
# Stop the Ruby container
docker stop monadic-chat-ruby-container
```

**Port 4567 already in use:**
```bash
# Find and kill the process
lsof -i :4567
kill -9 <PID>
```

### Production Mode Issues

**Containers not starting:**
```bash
# Rebuild containers
rake docker:rebuild
```

**Application not responding:**
```bash
# Check container logs
docker logs monadic-chat-ruby-container
```

## Best Practices

### Development Mode
1. Always use `rake server:debug` for development
2. Keep console open to monitor logs
3. Use verbose logging for debugging
4. Test with production settings before deployment

### Production Mode
1. Use built application for end users
2. Monitor logs in `/monadic/logs/`
3. Set up proper error handling
4. Configure automatic restarts

## Environment Variables

### Development-Specific
```bash
# ~/.monadic/config/env
DEVELOPMENT_MODE=true
SKIP_CONTAINER_CHECKS=true
HOT_RELOAD=true
```

### Production-Specific
```bash
# /monadic/config/env
PRODUCTION_MODE=true
AUTO_RESTART=true
LOG_ROTATION=true
```

## Performance Considerations

### Development Mode
- Higher memory usage (running services on host)
- Faster code iteration
- More CPU usage for logging
- No optimization

### Production Mode
- Lower memory footprint (containerized)
- Optimized performance
- Minimal logging overhead
- Better resource isolation