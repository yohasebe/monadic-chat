# Frequently Asked Questions

## Quick Navigation

- [Getting Started & Requirements](#getting-started-requirements)
- [Applications & Features](#applications-features)
- [File & Media Handling](#file-media-handling)
- [Voice & Audio](#voice-audio)
- [User Interface](#user-interface)
- [Configuration & Advanced Usage](#configuration-advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Install Options & Rebuild](#install-options-rebuild)

---

## Getting Started & Requirements

### Q: Do I need an OpenAI API token to use Monadic Chat? :id=api-token-requirement

**A**: No, an OpenAI API token is not mandatory. You have several options:

- **Ollama Plugin**: Use completely free, open-source models running locally
- **Other Providers**: Use Claude, Gemini, Mistral, Cohere, or other providers instead
- **Limited Features**: Some features work without any API tokens (basic UI exploration)

However, for the best experience with features like speech recognition and help system, an OpenAI API key is recommended.

### Q: What happens if I install a new version? :id=version-updates

**A**: When installing a new version:
- User settings (API tokens, configurations) are preserved
- Docker containers may rebuild based on changes
- Full rebuild occurs if Dockerfiles change
- Otherwise, only the Ruby container rebuilds (faster)

### Q: Can I use Monadic Chat offline? :id=offline-usage

**A**: Yes, with limitations:
- **Ollama models** work completely offline
- **Web search** and cloud-based features require internet
- **Local containers** continue working without internet
- **API-based models** need internet connection

---

## Applications & Features

### Q: What is the difference between Code Interpreter, Coding Assistant, and Jupyter Notebook apps? :id=app-differences

**A**: Each serves different purposes:

**Code Interpreter**
- Executes code automatically
- Best for data analysis and visualization
- Runs code in isolated Docker container
- Shows results immediately

**Coding Assistant**
- Helps write and debug code
- Doesn't execute code automatically
- Best for code generation and explanation
- Focuses on programming guidance

**Jupyter Notebook**
- Interactive notebook environment
- Persistent code execution
- Best for iterative development
- Saves work in .ipynb format

### Q: Can I extend the basic apps without knowing programming? :id=extend-apps

**A**: Yes! You can:
1. Modify system prompts directly in the UI
2. Adjust parameters like temperature and max tokens
3. Export your customized settings as JSON
4. Share configurations with others

For deeper customization, basic MDSL knowledge helps but isn't required for simple modifications.

### Q: What web search capabilities does Monadic Chat have? :id=web-search

**A**: Web search varies by provider:

**Native Search**:
- Providers that ship native search integrations (e.g., OpenAI Responses API search, Anthropic web search, Google Gemini, Perplexity Sonar, xAI Grok Live Search). Refer to each provider's documentation for the latest capabilities.

**Via Tavily API**:
- Mistral, Cohere, DeepSeek
- Requires separate Tavily API key

---

## File & Media Handling

### Q: Can I send data other than text to the AI agent? :id=media-support

**A**: Yes! Supported formats include:

**Direct Upload** (provider-dependent):
- Images (PNG, JPEG, GIF, WebP)
- PDFs
- Audio files
- Video files

**Via Content Reader App**:
- Office documents (Word, Excel, PowerPoint)
- Text files
- URLs for web content

**Processing Methods**:
- Direct analysis (vision models)
- Text extraction
- Transcription (audio/video)

### Q: Can I ask the AI agent about the contents of a PDF? :id=pdf-processing

**A**: Yes, three methods available:

1. **Direct Upload** (simplest)
   - Click attachment icon
   - Works with vision-capable models
   - Best for single PDFs

2. **PDF Navigator App**
   - Imports PDFs into vector database
   - Enables semantic search
   - Best for large document collections

3. **Code Interpreter**
   - Programmatic PDF analysis
   - Can extract specific data
   - Best for structured information extraction

---

## Voice & Audio

### Q: Can I use text-to-speech without API keys? :id=tts-without-api

**A**: Yes! Options include:

**Web Speech API** (built-in):
- Free browser-based TTS
- No API key required
- Quality varies by browser/OS

**Provider-Specific**:
- Gemini models include TTS
- Some providers have built-in voice features

### Q: How do I set up voice conversations? :id=voice-setup

**A**: For smooth voice interaction:

1. Enable **Easy Submit** (Enter key sends messages)
2. Enable **Auto Speech** (automatic TTS playback)
3. Use **Voice Chat** app for optimized experience
4. Configure STT model in settings

### Q: What is Auto TTS Realtime Mode and how can I adjust it? :id=auto-tts-realtime

**A**: Auto TTS Realtime Mode generates speech during text streaming instead of waiting for completion. You can customize this behavior:

**Buffer Size Configuration**:
- Adjustable via **Settings → Auto TTS Buffer Size** (20-200 characters)
- Default: 50 characters
- Environment variable: `AUTO_TTS_MIN_LENGTH`

**Tuning Guidelines**:
- **Smaller values (20-40)**: Faster response, may cause choppy audio
- **Larger values (60-100)**: Better fluency, increased initial delay
- **Language consideration**: Information-dense languages like Japanese may work better with smaller buffers

**When to adjust**:
- Increase if audio sounds choppy or fragmented
- Decrease if you want faster audio response
- Optimize based on your preferred language's characteristics

### Q: Why doesn't TTS read in my language? :id=tts-language

**A**: Language detection issues can occur when:
- Text contains mixed languages
- Language codes are incorrect
- Browser TTS doesn't support the language

**Solution**: Manually set language in TTS settings or use a TTS dictionary for pronunciation control.

### Q: Can I save synthesized speech? :id=save-speech

**A**: Yes, use the **Play** button on messages:
- Browser TTS: Use browser's audio recording
- API-based TTS: Audio can be saved programmatically
- Third-party tools can capture system audio

---

## User Interface

### Q: What do the message buttons do? :id=message-buttons

**A**: Each message has several action buttons:

- **Copy**: Copy message content (Markdown → HTML/text)
- **Speech**: Play as speech (when available)
- **Stop**: Stop speech playback
- **Delete**: Remove entire message
- **Edit**: Modify message content
- **Active/Inactive**: Toggle context inclusion

Hold Shift while clicking Copy for plain text instead of Markdown.

### Q: How are tokens calculated? :id=token-counting

**A**: Token counts shown include:
- Message content
- System prompts
- Context window
- Tool definitions
- Special formatting

The count updates dynamically and helps track API usage.

### Q: What is the Role selector for? :id=role-selector

**A**: The Role selector (User/Assistant/System) allows:
- **User**: Normal user messages
- **Assistant**: Simulate AI responses
- **System**: Add system-level instructions

Useful for testing, examples, or conversation templates.

### Q: Why do I see localhost security warnings? :id=localhost-warning

**A**: Browser warnings about localhost are normal:
- Monadic Chat serves UI locally
- No external server connection
- Data stays on your machine
- Warning can be safely ignored

---

## Configuration & Advanced Usage

### Q: How do I run Monadic Chat in server mode? :id=server-mode

**A**: Server mode allows multiple users:

1. Set `DISTRIBUTED_MODE=true` in config
2. Run `rake server`
3. Access from browser at server IP
4. Each user needs their own API keys
5. Sessions are isolated

### Q: Can I add Python libraries? :id=add-python-libraries

**A**: Yes, two methods:

**Method 1** - Custom setup script (recommended for permanent installation):
```bash
# ~/monadic/config/pysetup.sh
# Using uv (recommended)
uv pip install --no-cache pandas numpy scikit-learn

# Or using pip
pip install pandas numpy scikit-learn
```

**Method 2** - In-app installation (temporary, lost on container restart):
```python
# Using uv (recommended)
!uv pip install --no-cache library_name

# Or using pip
!pip install library_name
```

Changes persist across container restarts with Method 1 only.

### Q: How do I enable LaTeX apps (Concept Visualizer / Syntax Tree)? :id=enable-latex

**A**: Open `Actions → Install Options…` and enable LaTeX. The rebuild pulls TeX Live (xelatex/luatex), dvisvgm/pdf2svg, Ghostscript, and CJK packages so Concept Visualizer / Syntax Tree can render Japanese/Chinese/Korean diagrams. These apps also require an OpenAI or Anthropic API key; otherwise they remain hidden.

### Q: Why are “From URL / #doc” buttons hidden? :id=url-doc-hidden

**A**: When Selenium is disabled and no Tavily API key is configured, these buttons are hidden. If Selenium is disabled but a Tavily key exists, “From URL” uses Tavily. Enable Selenium to restore the original Selenium-based path.

### Q: Where can I find rebuild logs and health results? :id=rebuild-logs

**A**: Saving options no longer triggers a rebuild automatically. Run Rebuild from the main console when ready. Files are saved under `~/monadic/log/build/python/<timestamp>/`:
- `docker_build.log`, `post_install.log`, `health.json`, `meta.json`

### Q: Rebuilds are slow. How can I speed them up? :id=rebuild-speed

**A**: Monadic Chat uses smart build caching to automatically optimize rebuild speed:

**Automatic Optimization:**
- **Options unchanged**: Fast rebuild using Docker cache (~1-2 minutes)
- **Options changed**: Complete rebuild with `--no-cache` (~15-30 minutes)
- System automatically detects changes and chooses the appropriate strategy

**How it works:**
- Previous build options are saved to `~/monadic/log/python_build_options.txt`
- Before each build, current options are compared with saved options
- If any option differs (e.g., `INSTALL_LATEX` changed from `false` to `true`), `--no-cache` is used
- If options are unchanged, Docker cache is used for fast rebuilds

**Additional tips:**
- Change only necessary options to avoid triggering full rebuilds
- Keep `pysetup.sh` lightweight; heavy installs will dominate build time
- Stable network speeds significantly affect pip/apt install times

**After rebuild:** The Python container automatically restarts to use the new image immediately

### Q: What happens if a rebuild fails? :id=rebuild-failure

**A**: The current image is preserved (atomic update). Check the latest per-run folder for logs, fix issues (e.g., `~/monadic/config/pysetup.sh`), and retry.

### Q: When does the Ruby container rebuild run? Can I avoid frequent rebuilds? :id=ruby-rebuild-when

**A**: Ruby rebuilds only when necessary.
- At startup, Monadic Chat probes orchestration health; if Ruby isn’t ready to coordinate updated containers, it performs a one-time, cache-friendly refresh.
- Separately, if Gem dependencies changed (fingerprint = SHA256 of `Gemfile` + `monadic.gemspec`), Ruby is refreshed. The bundle layer is reused via Docker cache whenever possible.
- To force a clean rebuild for diagnostics, set `FORCE_RUBY_REBUILD_NO_CACHE=true` in `~/monadic/config/env`.

### Q: After clicking Stop, the web UI alternates between “Connecting…” and “Connection lost”. :id=stop-connecting-flicker

**A**: Intentional stops suppress noisy reconnect attempts in the embedded browser. The status shows “Stopped” during shutdown. If a tab was left open externally, refresh it after the next Start.

### Q: Do NLTK and spaCy options also download datasets/models automatically? :id=nltk-spacy-auto

**A**: No. The options install packages only to keep images lean.
- NLTK: install library only; datasets are not auto-downloaded.
- spaCy: install `spacy==3.7.5`; language models (e.g., `en_core_web_sm`, `en_core_web_lg`) are not auto-downloaded.
- Use `~/monadic/config/pysetup.sh` to fetch datasets/models during post-setup. See Python container docs for an example snippet.

### Q: How do I customize TTS pronunciation? :id=tts-dictionary

**A**: Create a pronunciation dictionary:

1. Create CSV file (no headers)
2. Format: `original,pronunciation`
3. Save to `~/monadic/data/`
4. Set path in TTS settings

Example:
```
AI,ay eye
SQL,sequel
```

### Q: What is MCP and how do I use it? :id=mcp-integration

**A**: MCP (Model Context Protocol) enables:
- External AI assistants to use Monadic Chat tools
- JSON-RPC 2.0 protocol
- Enable with `MCP_SERVER_ENABLED=true`
- Automatic tool discovery
- See [MCP Integration docs](/advanced-topics/mcp-integration.md)

---

## Troubleshooting

### Q: Why doesn't the app start even though Docker is running? :id=app-startup-issues

**A**: Check these common issues:

1. **Docker Desktop Status**
   - Ensure Docker is fully started
   - Check container status
   - Restart Docker if needed

2. **Port Conflicts**
   - Port 4567 must be free
   - Check for other services

3. **Container Health**
   - Run `docker ps` to verify
   - Check logs in Console Panel

4. **First Launch**
   - Initial container download takes time
   - Watch progress in console

### Q: What if containers fail to build? :id=container-build-failure

**A**: Troubleshooting steps:

1. **Check Logs**
   ```bash
   docker logs monadic-chat-ruby-container
   ```

2. **Clean Rebuild**
   - Delete containers in Docker Desktop
   - Restart Monadic Chat

3. **Disk Space**
   - Ensure 15GB+ free space
   - Clean Docker cache if needed

4. **Network Issues**
   - Check internet connection
   - Proxy settings if applicable

### Q: Can I reset an app to initial state? :id=app-reset

**A**: Yes, several options:

- **Soft Reset**: Click app name in menu
- **Clear Context**: Use context size 0 temporarily  
- **Full Reset**: File → New in Console Panel
- **Delete Data**: Remove saved conversations

### Q: What if code execution fails repeatedly? :id=code-execution-errors

**A**: Code Interpreter has retry mechanisms:
- Automatic error detection
- Up to 3 retry attempts
- Self-correction for common issues
- If persistent, check:
  - Python package availability
  - Memory limits
  - Code syntax errors

### Q: Can I have multiple conversations in parallel? :id=multiple-conversations

**A**: Monadic Chat supports one conversation at a time. However, you can:
- Save and export conversations
- Switch between different apps
- Use server mode for multi-user access
- Open multiple browser tabs

---

## Need More Help?

- Use **Monadic Help** app for AI-powered assistance
- Check [documentation](/) for detailed guides
- Review [configuration reference](/reference/configuration.md)
- See [quick start tutorial](/getting-started/quick-start.md) for basics
### Q: I rebuilt the Python or user containers and then Start failed. Do I need to rebuild Ruby too?

**A**: The Start command performs an orchestration health check and, if needed, automatically refreshes the Ruby control-plane once (using Docker cache) and continues startup. This is shown as informational messages in the console. If startup ultimately fails, check `~/monadic/log/docker_startup.log` (look for `Auto-rebuilt Ruby due to failed health probe`). You can tweak the health probe via `START_HEALTH_TRIES` and `START_HEALTH_INTERVAL` in `~/monadic/config/env`.
