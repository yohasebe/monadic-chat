# Advanced Configuration

This page covers Install Options, startup, build logs, browser tabs and environment variables.

## Install Options :id=install-options

**Actions → Install Options** opens the **Install Options** category of the Settings window. It holds optional components:

- **LaTeX**: **Install LaTeX (minimal set for diagrams)**, needed by Concept Visualizer and Syntax Tree
- **Python Libraries (CPU)**: nltk, spaCy, gensim, mediapipe, transformers
- **Music Analysis**: librosa + madmom, needed by the music analysis apps
- **System Tools (CLI)**: ImageMagick (`convert` / `mogrify`)
- **Privacy Filter — Additional Languages**: languages besides English for the Privacy Filter. They apply when you save; no rebuild is needed
- **Knowledge Base Quality Pack (Docling)**: a separate container for PDF extraction with layout analysis and OCR, with its OCR languages

The option table is in the [Configuration Reference](/reference/configuration.md).

### Panel Behavior

- **Save** keeps the window open; the Save button briefly shows a check mark.
- If you close the window with unsaved changes, a dialog offers **Close** (discard the changes) and **Save and Close**.
- Labels, descriptions and dialogs follow the UI language.

### Rebuild Process

Saving options does not start a rebuild. To apply the Python options, run **Actions → Build Python Container**. The new image is built and checked first, and replaces the current one only when the check passes. Progress appears in the main console.

If saved options are not yet in the images, the next **Start** asks whether to rebuild, with **Rebuild and Start**, **Start Anyway** and **Cancel**.

### NLTK and spaCy Setup

- Enabling `nltk` installs the library only (no datasets/corpora are downloaded automatically)
- Enabling `spacy` installs the library only (no language models downloaded)

To download data and models, write a `~/monadic/config/pysetup.sh`. It runs at the end of the Python container build, so what it installs is part of the image. When this file exists, the Python container is built on your computer instead of using the prebuilt image.

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

python - <<'PY'
import nltk
nltk.download('all')
PY
```

?> Downloading "all" takes several GB and a long time. Do not download into `/monadic/data`: the shared folder is mounted there when the container runs, so files put there during the build are not visible.

## Startup Health Tuning :id=startup-health-tuning

When you click **Start**, Monadic Chat checks that the containers respond. If the Ruby container does not become ready and Docker reports it as unhealthy, it is rebuilt once with the Docker cache and started again (set `AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=false` to turn this off). A green "Ready" means that startup has finished.

### Probe Tuning

Health probe behavior can be tuned with `START_HEALTH_TRIES` and `START_HEALTH_INTERVAL` in `~/monadic/config/env` — see [Environment Variables](#environment-variables) below.

## Dependency-Aware Ruby Rebuild :id=ruby-rebuild

The Ruby image carries a fingerprint of its Gem dependencies (SHA256 of `Gemfile` and `monadic.gemspec`) as the label `com.monadic.gems_hash`. When it differs from the current files, the Ruby container is rebuilt with the Docker cache, so the bundle layer is reused when possible.

### Force Clean Rebuild

For troubleshooting, a clean rebuild can be forced with `FORCE_RUBY_REBUILD_NO_CACHE` in `~/monadic/config/env` — see [Environment Variables](#environment-variables) below.

## Build Logs :id=build-logs

Logs are overwritten on each build.

### Python Build Logs

- `~/monadic/log/docker_build_python.log` (includes the output of `pysetup.sh`)
- `~/monadic/log/python_health.json`
- `~/monadic/log/python_meta.json`

### Other Build Logs

- Ruby and user containers: `~/monadic/log/docker_build.log`

## Multi-Tab Session Management :id=multi-tab-sessions

You can open Monadic Chat in several browser tabs at once. Each tab is a separate conversation session:

**Session Isolation:**
- Each tab has a unique tab ID (kept in `sessionStorage`) that identifies its WebSocket session on the server
- Conversation state — messages, app selection, and parameter changes — is per tab and never leaks into other tabs
- Reloading a tab keeps its session; opening a new tab starts a fresh one
- Different browsers, browser profiles, and incognito/private windows are likewise separate sessions

**Shared per browser:**
- Preferences stored in the browser (for example the UI language and the speech-to-text model, kept in cookies) are shared by all tabs in the same browser profile

## Environment Variables :id=environment-variables

Advanced configuration via `~/monadic/config/env`:

### Docker Build Control

```
# Force Ruby rebuild without cache
FORCE_RUBY_REBUILD_NO_CACHE=true

# Health probe settings
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2

# Rebuild Ruby once when it is unhealthy at Start (default true)
AUTO_REFRESH_RUBY_ON_HEALTH_FAIL=true
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

See the [Configuration Reference](/reference/configuration.md) for the complete list of environment variables.
