# Docker Architecture & Container Management

## Container Structure

Monadic Chat uses multiple Docker containers for different functionalities.
The authoritative service set is the `docker/services/` directory (one
subdirectory per service, each with its own Dockerfile + compose file,
included from `docker/services/compose.yml`):

- **Ruby** (`monadic-chat-ruby-container`): Main application server (Falcon/Rack with 2 workers for personal use)
- **Qdrant** (`monadic-chat-qdrant-container`): Vector database for embeddings (Help system, PDF Library / Knowledge Base)
- **Embeddings** (`monadic-chat-embeddings-container`): Local embedding service (`multilingual-e5-base`)
- **Python** (`monadic-chat-python-container`): JupyterLab, Python tools & script execution
- **Selenium** (`monadic-chat-selenium-container`): Web automation for capture/search
- **Privacy** (`monadic-chat-privacy-container`): PII masking service for the Privacy Filter
- **Extractor** (`monadic-chat-extractor-container`): Document extraction service (Docling + RapidOCR)

Native Ollama is not a container: the Ruby service reaches the host's
Ollama via `host.docker.internal:11434`.

PostgreSQL/PGVector was removed in beta.16 (replaced by Qdrant + the
embeddings container). See `docs_dev/qdrant_embeddings_migration.md`.

## Container Lifecycle

### Development Mode (`rake server:debug`)
- Ruby container NOT used (local Ruby environment; the Ruby container is stopped)
- Peer containers (Qdrant, embeddings, Python, etc.) started as needed
- Useful for Ruby code iteration

### Production Mode
- All containers managed by Docker Compose (`docker/services/compose.yml`)
- Ruby app runs inside the Ruby container

### On-Demand Container Startup (Compose Profiles)

Optional containers use Docker Compose **profiles** and are NOT started by
default. Only the default services (Ruby + the `BASE_SERVICES` defined in
`lib/monadic/utils/container_dependencies.rb` — currently Qdrant +
embeddings, so the Help system always works) start on `docker compose up`.

| Container | Profile | Started When |
|-----------|---------|-------------|
| Ruby | (none) | Always at startup |
| Qdrant | (none) | Always at startup (base service) |
| Embeddings | (none) | Always at startup (base service) |
| Python | `python` | App requires code execution, Jupyter, or data analysis |
| Selenium | `selenium` | App requires web automation (Web Insight, AutoForge, etc.) |
| Privacy | `privacy` | Privacy Filter enabled for the session |
| Extractor | `extractor` | App requires document extraction |

Container startup is triggered automatically when the user selects an app that requires it.
The `ContainerDependencies` module (`lib/monadic/utils/container_dependencies.rb`) determines
which services each app needs based on MDSL settings (tool groups, jupyter flag, pdf_vector_storage).

Manual startup: `monadic.sh ensure-service <name>` (e.g. `python`, `selenium`, `privacy`)

**Exception — Full lifecycle operations include all profiles**: `build` (Build All), `update`,
`down_docker_compose`, `stop_docker_compose`, and `remove_containers` must operate on every
service regardless of on-demand startup. Two profile sets exist (defined once at the top of
`monadic.sh`; consult those definitions for the current lists): `ALL_PROFILES_UP` is
flag-gated and used for start/build/pull, while `ALL_PROFILES_DOWN` is unconditional and used
for stop/down/remove — feature flags gate startup, never teardown, so a container started
while a flag was on is still stopped after the flag is turned off.
`spec/unit/compose_profile_completeness_spec.rb` pins both sets against the `profiles:` keys
in the compose files.

### Prebuilt Service Images (ghcr.io)

The **embeddings**, **privacy**, **extractor**, **selenium**, and
**qdrant** images are NOT built locally: they are published as multi-arch
(linux/amd64 + linux/arm64) manifests to ghcr.io by
`.github/workflows/publish-images.yml` and pulled on demand. This is
possible because their content is user-independent — language/OCR
selection became runtime env (`PRIVACY_LANGS` / `EXTRACTOR_LANGS` /
`EXTRACTOR_OCR`, injected via compose `environment:`) rather than build
args. The **python** default image (all install options off) is also
published and doubles as the `--cache-from` source for option-enabled
local builds. qdrant is a version-pinned mirror of the upstream image
(see `docker/services/qdrant/Dockerfile` for the pin and bump procedure)
so a mutable upstream `:latest` can never reach users outside a release;
with selenium prebuilt as well, user machines no longer contact Docker
Hub at runtime at all (Hub remains only as the base-image source for
local builds of ruby and option-enabled python).

Key mechanics:

- The services' `compose.yml` files declare `image: ghcr.io/yohasebe/monadic-<name>:latest`
  with **no `build:` section**, so every `docker compose up` / `pull` path
  (production start, `ensure-service`, rake test/help tasks) pulls instead
  of building. Layer-diff downloads make refreshes cheap.
- `monadic.sh ensure-service embeddings|privacy|extractor|qdrant|selenium`
  pulls the image when missing before reporting `*_NOT_BUILT`.
- `build_privacy_container` / `build_extractor_container` pull in
  production and build locally only in development (`MONADIC_DEV=true`),
  via the per-service `compose.build.yml` overlay. The overlay resolves
  its build context through `MONADIC_ROOT_DIR` (exported by `monadic.sh`)
  because relative paths in `-f` overlay files resolve against the first
  compose file's directory, which varies between invocation paths.
- The full build (`build_docker_compose`) pulls embeddings, qdrant and
  selenium (+ privacy/extractor when enabled) before building the
  locally-built images, and the image verification step fails the build
  when a required pull did not produce an image.
- Tag policy: `:latest` (the default consumed by user installs) moves only
  via main pushes (release path) or `workflow_dispatch`; dev pushes publish
  `:dev` instead, which dev-branch CI consumes (`MONADIC_IMAGE_TAG=dev` in
  specs.yml). A release also publishes an immutable `:<version>` tag
  (`workflow_dispatch` with the `version` input) for rollback. Users can
  pin or switch tags via `MONADIC_IMAGE_TAG` in `~/monadic/config/env`.
- The ghcr.io packages must be public (one-time setting per package after
  the first publish) for anonymous pulls to work.
- Migration: `remove_legacy_prebuilt_images` (called on start) deletes the
  pre-ghcr locally built `yohasebe/monadic-*` images plus the pre-unification
  `yohasebe/selenium` and upstream `qdrant/qdrant` images.

### Restart Policies

All containers use the Docker default restart policy (`no`): lifecycle is
owned by Electron/Compose, which also avoids blocking Docker Resource
Saver. On-demand containers have no independent lifecycle.

### Python image build (verified promotion)
- Rebuild is invoked via `docker/monadic.sh build_python_container`.
- Build to a temporary tag → run post-setup if present (`~/monadic/config/pysetup.sh`) → health checks → retag to version/latest only on success.
- On failure, the current image is preserved (no rollback needed).
- For each run, logs/metadata/health are saved under `~/monadic/log/build/python/<timestamp>/`.

## Container Commands

```bash
# View running containers
docker ps | grep monadic

# View container logs
docker logs monadic-chat-ruby-container -f

# Enter container shell
docker exec -it monadic-chat-ruby-container /bin/bash

# Restart specific container
docker restart monadic-chat-python-container

# Clean rebuild (compose)
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## Volume Mounts

- `~/monadic/data` → `/monadic/data` (shared data)
- `~/monadic/config` → `/monadic/config` (API keys, settings)
- `~/monadic/log` → `/monadic/log` (logs)
  - Python Rebuild per-run: `~/monadic/log/build/python/<timestamp>/`

## Port Mappings (defaults)

Host-published ports (see each service's `compose.yml` for the authoritative list):

- 4567: Ruby web server
- 8889: JupyterLab (Python container)
- 4444 / 5900 / 7900: Selenium Grid / VNC
- 11434: Ollama API (native on host, not a container)

Qdrant, embeddings, Privacy, and Extractor expose no host ports; they are
reached only over the internal `monadic-chat-network`.

Published ports use the `HOST_BINDING` environment variable to control the bind address:
- **Default** (`127.0.0.1`): Ports are only accessible from localhost (Standalone mode)
- **Server mode** (`0.0.0.0`): Ports are accessible from the network (set via `HOST_BINDING=0.0.0.0` in `~/monadic/config/env`)

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

# Change port in the service's compose.yml if needed
```
### Slow rebuilds / cache misses
- The Python Dockerfile is split into a base pip layer and per-option layers (one RUN per library) to leverage cache.
- Toggling options or LaTeX/ImageMagick only re-executes the affected layers, avoiding full rebuilds.
