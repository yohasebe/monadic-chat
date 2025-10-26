# Python Service Documentation

This section contains internal documentation for Monadic Chat's Python service, which provides computational tools and Jupyter notebook integration.

## Contents

- [Jupyter Controller Tests](jupyter_controller_tests.md) - Testing infrastructure for Jupyter integration

## Overview

The Python service is a Flask-based API server that provides:

- **Token Counting** - Count tokens in text using tiktoken library
- **Encoding Management** - Get encoding names and decode token sequences
- **JupyterLab Access** - Direct JupyterLab interface on port 8889 (separate from Flask API)
- **Scientific Computing Libraries** - NumPy, Pandas, Matplotlib available in JupyterLab environment
- **Optional Packages** - LaTeX, NLTK, spaCy, and more (configurable via Install Options)

## Architecture

- **Flask API Server** (`docker/services/python/flask/flask_server.py`) - Token counting REST API
- **JupyterLab Server** - Direct notebook interface (port 8889)
- **Execution Environment** - Isolated Python runtime with scientific libraries
- **Docker Container** - Standalone service with optional dependencies

## Key Flask API Endpoints

- `GET /health` - Health check for service availability
- `GET /warmup` - Preload common encodings to reduce latency
- `POST /get_encoding_name` - Get tiktoken encoding name for a model
- `POST /count_tokens` - Count tokens in text
- `POST /get_tokens_sequence` - Get comma-separated token sequence
- `POST /decode_tokens` - Decode tokens back to original text

## Install Options

The Python container supports optional package installation via **Actions → Install Options**:

- **LaTeX** - Document typesetting (texlive-xetex, texlive-fonts-recommended, cm-super)
- **NLTK** - Natural Language Toolkit with common corpora
- **spaCy** - Industrial-strength NLP (with en_core_web_sm model)
- **scikit-learn** - Machine learning library
- **transformers** - Hugging Face transformers library

Configuration stored in `~/monadic/config/env` and tracked for smart rebuild detection.

## Related Documentation

- [Docker Build Caching](../docker-build-caching.md) - Smart caching for Python container builds
- [Docker Architecture](../docker-architecture.md) - Multi-container orchestration

See also:
- `docker/services/python/` - Python service source code
- `docker/services/python/requirements.txt` - Python dependencies
