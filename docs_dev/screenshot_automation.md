# UI Screenshot Automation

This note explains how to programmatically capture screenshots of the Monadic Chat web UI for documentation.

## Overview

- Uses the existing Selenium service and the Python container’s CLI tools
  - `docker/services/python/scripts/cli_tools/webpage_fetcher.py`
  - Supports full-page PNG capture and element-level capture via CSS selectors
- A helper script `bin/capture_ui.sh` wraps common operations

## Prerequisites

- Start Monadic Chat (Ruby/Python/Selenium containers must be running)
- Output directory defaults to `~/monadic/data/screenshots` and is mounted in the Python container as `/monadic/data/screenshots`

## Quick Start

Capture a specific element (e.g., status message):

```bash
bin/capture_ui.sh \
  --url http://localhost:4567 \
  --element '#status-message' \
  --out ~/monadic/data/screenshots
```

Capture the full page:

```bash
bin/capture_ui.sh \
  --url http://localhost:4567 \
  --fullpage true \
  --out ~/monadic/data/screenshots
``;

Options:
- `--url <url>`: target page (default: `http://localhost:4567`)
- `--element <css>`: CSS selector for element screenshot (omit to capture viewport or use `--fullpage true`)
- `--fullpage true|false`: full page capture (default: false)
- `--out <host-dir>`: output directory on host (default: `~/monadic/data/screenshots`)
- `--timeout <sec>`: page/script timeout (default: 30)

## Notes and Tips

- The Selenium service is addressed as `selenium_service:4444` inside the Python container; the helper script calls the Python CLI tool via `docker exec`.
- For consistent visual output, prefer a stable theme/state in the UI (language, zoom, and panel open/close state).
- Element selectors commonly used:
  - `#status-message`, `#start`, `#apps`, `#model`, `#websearch-badge`, `#monadic-spinner`
- For multiple captures, wrap commands in a small shell script and provide a timestamped subfolder.

## Direct CLI (no wrapper)

You can also invoke the tool directly:

```bash
docker exec -i monadic-chat-python-container \
  python /monadic/scripts/cli_tools/webpage_fetcher.py \
  --url http://localhost:4567 \
  --mode png \
  --element '#status-message' \
  --filepath /monadic/data/screenshots \
  --timeout-sec 30
```

## Troubleshooting

- "Python/Selenium container not running": Start Monadic Chat first.
- Blank or empty image removed: the page may not be fully rendered yet; increase `--timeout`.
- Element not found: Double-check the CSS selector; use the browser dev tools to verify.

