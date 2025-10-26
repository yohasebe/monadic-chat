# Advanced Configuration

This page covers advanced configuration options for Monadic Chat, including Install Options, Server Mode, and container management.

## Install Options :id=install-options

From the app menu **Actions → Install Options…**, you can choose optional components for the Python container.

### Available Options

- **LaTeX** (with TeX Live + CJK): Enables Concept Visualizer / Syntax Tree with built-in Japanese/Chinese/Korean support (requires OpenAI or Anthropic key)
- **Python libraries (CPU)**: `nltk`, `spacy`, `scikit-learn`, `gensim`, `librosa`, `transformers`
- **Tools**: ImageMagick (`convert`/`mogrify`)

### Panel Behavior

- The Install Options window is modal and matches the Settings panel size
- "Save" does not close the window; a green check briefly confirms success
- If you click "Close" with unsaved changes, a confirmation dialog offers "Save and Close" or "Cancel"
- All labels, descriptions, and dialogs follow your UI language (EN/JA/ZH/KO/ES/DE/FR)

### Rebuild Process

Saving options does not trigger a rebuild automatically. When ready, run **Rebuild** from the main console to update the Python image.

The update is atomic (build → verify → promote on success) and progress/logs appear in the main console. A per-run summary and health check are written alongside the logs.

### NLTK and spaCy Setup

- Enabling `nltk` installs the library only (no datasets/corpora are downloaded automatically)
- Enabling `spacy` installs the library only (no language models downloaded)

**Recommended**: Add a `~/monadic/config/pysetup.sh` to fetch what you need during post-setup:

```sh
#!/usr/bin/env bash
set -euo pipefail

# NLTK packages
python - <<'PY'
import nltk
for pkg in ["punkt","stopwords","averaged_perceptron_tagger","wordnet","omw-1.4","vader_lexicon"]:
    nltk.download(pkg, raise_on_error=True)
PY

# spaCy models
python -m spacy download en_core_web_sm
python -m spacy download en_core_web_lg
```

#### For Japanese and Additional Corpora

```sh
#!/usr/bin/env bash
set -euo pipefail

# spaCy Japanese models (pick one)
python -m spacy download ja_core_news_sm
# or: ja_core_news_md / ja_core_news_lg

# NLTK extra corpora
python - <<'PY'
import nltk
for pkg in ["brown","reuters","movie_reviews","conll2000","wordnet_ic"]:
    nltk.download(pkg, raise_on_error=True)
PY
```

#### Full NLTK Download (All Datasets)

```sh
#!/usr/bin/env bash
set -euo pipefail

export NLTK_DATA=/monadic/data/nltk_data
mkdir -p "$NLTK_DATA"

python - <<'PY'
import nltk, os
nltk.download('all', download_dir=os.environ.get('NLTK_DATA','/monadic/data/nltk_data'))
PY
```

?> **Note**: Downloading "all" is large (GBs) and may take considerable time.

## Startup Health Tuning :id=startup-health-tuning

When you click **Start**, the system runs an orchestration health check. If needed, the Ruby control-plane is automatically refreshed once (cache-friendly) and startup proceeds.

This is presented as informational prompts; finally a green "Ready" indicates success.

### Probe Tuning

You can tune health probe behavior via `~/monadic/config/env`:

```
# Health probe window
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

## Dependency-Aware Ruby Rebuild :id=ruby-rebuild

Ruby is rebuilt only when the Gem dependency fingerprint (SHA256 of `Gemfile` + `monadic.gemspec`) changes.

The image carries this value as `com.monadic.gems_hash`; when it differs from your working copy, a refresh is performed using Docker cache so the bundle layer is reused whenever possible.

### Force Clean Rebuild

To force a clean rebuild for troubleshooting, set in `~/monadic/config/env`:

```
FORCE_RUBY_REBUILD_NO_CACHE=true
```

## Build Logs :id=build-logs

Logs are overwritten each run:

### Python Build Logs

- `~/monadic/log/docker_build_python.log`
- `~/monadic/log/post_install_python.log`
- `~/monadic/log/python_health.json`
- `~/monadic/log/python_meta.json`

### Other Build Logs

- Ruby/User/Ollama build: `~/monadic/log/docker_build.log`

## Server Mode Configuration :id=server-mode

?> **Note: Monadic Chat is designed primarily for standalone mode. Server mode should only be used when you need to share the service with multiple users on a local network.**

By default, Monadic Chat runs in standalone mode with all components on a single machine.

### Enabling Server Mode

1. Open Settings by clicking the gear icon
2. In "Application Mode" dropdown, select "Server Mode"
3. Click "Save"
4. Restart the application

### Server Mode Behavior

In server mode:
- The server hosts all Docker containers and web services
- Multiple clients can connect via their web browsers
- Network URLs (like Jupyter notebooks) use the server's external IP address
- Clients can access resources hosted on the server

See [Server Mode Architecture](../docker-integration/basic-architecture.md#server-mode) for more details.

## Environment Variables :id=environment-variables

Advanced configuration via `~/monadic/config/env`:

### Docker Build Control

```
# Force Ruby rebuild without cache
FORCE_RUBY_REBUILD_NO_CACHE=true

# Health probe settings
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```

### PDF Storage

```
# PDF storage mode (local|cloud)
PDF_STORAGE_MODE=local

# Fallback for backward compatibility
PDF_DEFAULT_STORAGE=local
```

### Logging

```
# Enable extra logging
EXTRA_LOGGING=true
```

### MCP Server

```
# Enable MCP server
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

See [Setting Items](setting-items.md) for complete configuration reference.
