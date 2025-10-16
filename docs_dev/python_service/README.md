# Python Service Documentation

This section contains internal documentation for Monadic Chat's Python service, which provides computational tools and Jupyter notebook integration.

## Contents

- [Jupyter Controller Tests](jupyter_controller_tests.md) - Testing infrastructure for Jupyter integration

## Overview

The Python service is a Flask-based API server that provides:

- **Code Execution** - Safe execution of Python code in isolated environments
- **Jupyter Integration** - Notebook creation, execution, and management
- **Scientific Computing** - NumPy, Pandas, Matplotlib, and other libraries
- **Optional Packages** - LaTeX, NLTK, spaCy, and more (configurable via Install Options)

## Architecture

- **Flask API Server** (`docker/services/python/app.py`) - HTTP REST API
- **Jupyter Controller** - Notebook lifecycle management
- **Execution Environment** - Isolated Python runtime with scientific libraries
- **Docker Container** - Standalone service with optional dependencies

## Key Endpoints

- `POST /execute` - Execute Python code
- `POST /notebook/create` - Create new Jupyter notebook
- `POST /notebook/execute` - Execute notebook cells
- `GET /notebook/status` - Check notebook execution status

## Install Options

The Python container supports optional package installation via **Actions → Install Options**:

- **LaTeX** - Document typesetting (texlive-xetex, texlive-fonts-recommended, cm-super)
- **NLTK** - Natural Language Toolkit with common corpora
- **spaCy** - Industrial-strength NLP (with en_core_web_sm model)
- **scikit-learn** - Machine learning library
- **transformers** - Hugging Face transformers library

Configuration stored in `~/monadic/config/env` and tracked for smart rebuild detection.

## Related Documentation

- [Docker Build Caching](/docker-build-caching.md) - Smart caching for Python container builds
- [Docker Architecture](/docker-architecture.md) - Multi-container orchestration

See also:
- `docker/services/python/` - Python service source code
- `docker/services/python/requirements.txt` - Python dependencies
