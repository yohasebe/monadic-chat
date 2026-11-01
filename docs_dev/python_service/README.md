# Python Service Documentation

Internal documentation for the Python service (`docker/services/python/`), which runs Python tools for the apps and JupyterLab.

## Contents

- [Jupyter Controller Tests](jupyter_controller_tests.md) - Tests for the Jupyter integration

## Container

- **JupyterLab** on port 8889, bound to `127.0.0.1`.
- **Base packages** (installed in `Dockerfile` with pinned versions): NumPy, pandas, statsmodels, scikit-learn, Matplotlib, seaborn, SymPy, Plotly, pdfplumber, Selenium client, OpenCV, Graphviz and others; Silero VAD on onnxruntime for speech segments.
- **Scripts** under `scripts/` (`cli_tools`, `converters`, `music`, `services`, `utilities`), run by the Ruby side with `send_command`.

## Install Options

**Actions → Install Options** turns on optional layers. Each is a build `ARG` in `Dockerfile` and an entry of `PY_OPTIONS` in `docker/monadic.sh`:

| Option | Installs |
|---|---|
| `INSTALL_LATEX` | TeX Live (XeTeX, LuaTeX, CJK and Japanese, science, PSTricks), latexmk, Ghostscript, dvisvgm, pdf2svg |
| `PYOPT_NLTK` | nltk |
| `PYOPT_SPACY` | spaCy 3.7 |
| `PYOPT_GENSIM` | gensim |
| `PYOPT_LIBROSA` | librosa, soundfile, midiutil, pretty_midi, madmom (librosa only if madmom fails to build) |
| `PYOPT_MEDIAPIPE` | mediapipe (skipped when no wheel is available) |
| `PYOPT_TRANSFORMERS` | transformers, accelerate |
| `IMGOPT_IMAGEMAGICK` | ImageMagick |

The settings are stored in `~/monadic/config/env`. Build behavior is described in [Docker Build Caching](../docker-build-caching.md).

## Related Documentation

- [Docker Build Caching](../docker-build-caching.md)
- [Docker Architecture](../docker-architecture.md)
- `docker/services/python/Dockerfile`
