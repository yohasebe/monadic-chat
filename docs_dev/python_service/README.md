# Python Service Documentation

This section contains internal documentation for Monadic Chat's Python service, which provides computational tools and Jupyter notebook integration.

## Contents

- [Jupyter Controller Tests](jupyter_controller_tests.md) - Testing infrastructure for Jupyter integration

## Overview

The Python service provides computational tools and a JupyterLab environment:

- **JupyterLab Access** - Direct JupyterLab interface on port 8889
- **Scientific Computing Libraries** - NumPy, Pandas, Matplotlib available in JupyterLab environment
- **Optional Packages** - LaTeX, NLTK, spaCy, and more (configurable via Install Options)

## Architecture

- **JupyterLab Server** - Direct notebook interface (port 8889)
- **Execution Environment** - Isolated Python runtime with scientific libraries
- **Docker Container** - Standalone service with optional dependencies

Note: Token counting was previously handled by a Flask API server in this container, but has been migrated to a native Ruby implementation (`tiktoken_ruby` gem) for better performance.

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
