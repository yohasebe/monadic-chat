# FAQ: Setup and Settings

##### Q: Do I need an OpenAI API token to use Monadic Chat? :id=openai-api-token-requirement

**A**: An OpenAI API token is not necessarily required if you do not use functions such as speech recognition, speech synthesis, and text embedding. You can also use APIs such as Anthropic Claude, Google Gemini, Cohere, Mistral AI, DeepSeek, and xAI Grok.

If you do not want to use commercial APIs, you can use Ollama to run local language models:
1. Install Ollama from [https://ollama.com/download](https://ollama.com/download)
2. Pull models using the `ollama pull <model>` command (e.g., `ollama pull llama3.2`)
3. Use the Chat app with Ollama provider selected

For detailed information on using Ollama with Monadic Chat, see [Using Ollama](/advanced-topics/ollama.md).

---

##### Q: Rebuilding Monadic Chat (rebuilding the containers) fails. What should I do? :id=container-rebuild-failures

**A**: Check the contents of the log files in the log folder.

If you are developing additional apps or modifying existing apps, check the contents of `server.log` in the log folder. If an error message is displayed, correct the app code based on the error message.

If you are adding libraries to the Python container using `pysetup.sh`, error messages may be displayed in `docker_build.log`. Check the error message and correct the installation script.

---

##### Q: What is the difference between UI Language and Conversation Language? :id=ui-vs-conversation-language

**A**: Monadic Chat has two separate language settings:

- **UI Language**: Controls the interface language of the Electron app (menus, buttons, dialogs). This is set in the Electron Settings panel and affects only the application interface.

- **Conversation Language**: Controls the language used for AI responses and speech recognition/synthesis. This is set in the Web UI and affects:
  - AI response language
  - Speech-to-Text (STT) language detection
  - Text-to-Speech (TTS) language
  - Text direction (RTL for Arabic, Hebrew, Persian, Urdu)

These settings are independent, allowing you to use the app interface in one language while conversing with AI in another.

---

##### Q: How do I enable the LaTeX-based apps (Concept Visualizer / Syntax Tree)? :id=enable-latex

**A**: Open `Actions → Install Options…` and enable the LaTeX option, then rebuild the Python container. The rebuild installs TeX Live (XeLaTeX/LuaLaTeX), dvisvgm/pdf2svg, Ghostscript, and CJK font packages, so Concept Visualizer and Syntax Tree can render diagrams that include Japanese, Chinese, or Korean text. These apps are provided for OpenAI and Anthropic Claude, so they remain hidden unless one of those API keys is configured.

---

##### Q: Do the NLTK and spaCy install options also download datasets and models automatically? :id=nltk-spacy-auto

**A**: No. To keep the image lean, the options install the libraries only:

- **NLTK**: the library is installed; corpora and datasets are not downloaded.
- **spaCy**: the library is installed; language models (e.g., `en_core_web_sm`) are not downloaded.

Use `~/monadic/config/pysetup.sh` to fetch datasets and models during post-install. See [Adding libraries with pysetup.sh](../docker-integration/python-container.md#adding-libraries-with-pysetupsh) for examples.

---

##### Q: Where can I find rebuild logs and health-check results? :id=rebuild-logs

**A**: Saving Install Options only updates the configuration. The rebuild itself runs at the next Start (a dialog offers "Rebuild and Start") or when you run `Actions → Build Python Container`. Build artifacts are written as files in `~/monadic/log/`:

- `docker_build_python.log` — Docker build output
- `post_install_python.log` — post-install (`pysetup.sh`) output
- `python_health.json` — post-build health check results
- `python_meta.json` — build metadata
- `python_build_options.txt` — the option set used for the last build

---

##### Q: Rebuilds are slow. How can I speed them up? :id=rebuild-speed

**A**: Monadic Chat picks the fastest build strategy automatically:

- **No install options enabled**: the prebuilt default Python image is downloaded instead of being built locally (seconds to minutes).
- **Some options enabled**: a local build reuses the prebuilt image's layers via Docker cache, so only the layers for the enabled options are actually built.
- **Manual build (`Actions → Build Python Container`)**: a clean `--no-cache` rebuild for reliability; this is the slowest path.

Additional tips: keep `~/monadic/config/pysetup.sh` lightweight (heavy installs dominate build time), and note that network speed strongly affects download-heavy steps. After a rebuild, the Python container restarts automatically to use the new image.

---

##### Q: What happens if a rebuild fails? :id=rebuild-failure

**A**: The currently working image is preserved — a new image replaces the old one only after a successful build (atomic update). Check `docker_build_python.log` and `post_install_python.log` in `~/monadic/log/`, fix the issue (for example, in `~/monadic/config/pysetup.sh`), and retry.

---

##### Q: When does the Ruby container rebuild run? Can I avoid frequent rebuilds? :id=ruby-rebuild-when

**A**: The Ruby container rebuilds only when necessary:

- **App version updated**: after installing a new version, Start rebuilds the Ruby container using Docker cache (fast).
- **Gem dependencies changed**: a fingerprint (SHA-256 of `Gemfile` + `monadic.gemspec`) is compared with the current image; on mismatch, Ruby is rebuilt, reusing the bundle layer via Docker cache whenever possible.
- **Failed startup health probe**: at Start, orchestration health is probed (for example, after rebuilding the Python container). If the Ruby container is unhealthy, a one-time cache-friendly refresh runs automatically and startup continues. This is recorded in `~/monadic/log/docker_startup.log` (`Auto-rebuilt Ruby due to failed health probe`). The probe can be tuned with `START_HEALTH_TRIES` and `START_HEALTH_INTERVAL` in `~/monadic/config/env`.

To force a clean rebuild for diagnostics, set `FORCE_RUBY_REBUILD_NO_CACHE=true` in `~/monadic/config/env` or use `Actions → Build Ruby Container`.

