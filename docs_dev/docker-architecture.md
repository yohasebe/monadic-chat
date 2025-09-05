# Docker Architecture & Container Management

## Container Structure

Monadic Chat uses multiple Docker containers for different functionalities:

- **Ruby** (`monadic-chat-ruby-container`): Main application server (Thin/Rack)
- **Python** (`monadic-chat-python-container`): Flask API for Python tools & embeddings
- **PostgreSQL/PGVector** (`monadic-chat-pgvector-container`): Vector database for embeddings
- **Selenium** (`monadic-chat-selenium-container`): Web automation for capture/search
- **Ollama** (`monadic-chat-ollama-container`): Local LLM support (optional)

## Container Lifecycle

### Development Mode (`rake server:debug`)
- Ruby container NOT used (local Ruby environment)
- Other containers started as needed
- Useful for Ruby code iteration

### Production Mode
- All containers managed by Docker Compose (`docker/services/compose.yml`)
- Ruby app runs inside the Ruby container
- Auto-restart on failures (compose policies)

## Container Commands

```bash
# View running containers
docker ps | grep monadic

# View container logs
docker logs monadic_ruby -f

# Enter container shell
docker exec -it monadic_ruby /bin/bash

# Restart specific container
docker restart monadic_python

# Clean rebuild (compose)
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## Volume Mounts

- `~/monadic/data` → `/monadic/data` (shared data)
- `~/monadic/config` → `/monadic/config` (API keys, settings)
- `~/monadic/log` → `/monadic/log` (logs)

## Port Mappings (defaults)

- 4567: Ruby web server
- 5070: Python Flask API (see `PYTHON_PORT` in docs)
- 5433: PostgreSQL/PGVector
- 4444: Selenium Grid
- 11434: Ollama API (when enabled)

## Troubleshooting

### Container won't start
```bash
# Check logs (example for Ruby)
docker logs monadic-chat-ruby-container --tail 100

# Recreate via compose (project directory is docker/services)
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

### Port conflicts
```bash
# Find process using port
lsof -i :4567

# Change port in docker/compose.yml if needed
```
