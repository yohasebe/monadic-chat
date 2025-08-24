# Frequently Asked Questions

## Quick Navigation

- [Getting Started & Requirements](#getting-started-requirements)
- [Applications & Features](#applications-features)
- [File & Media Handling](#file-media-handling)
- [Voice & Audio](#voice-audio)
- [User Interface](#user-interface)
- [Configuration & Advanced Usage](#configuration-advanced-usage)
- [Troubleshooting](#troubleshooting)

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
- OpenAI (gpt-4o-search models)
- Anthropic Claude (web_search tool)
- Google Gemini (Google Search)
- Perplexity (built-in)
- xAI Grok (Live Search)

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

**Method 1** - Custom setup script:
```bash
# ~/monadic/config/pysetup.sh
pip install pandas numpy scikit-learn
```

**Method 2** - In-app installation:
```python
!pip install library_name
```

Changes persist across container restarts with Method 1.

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

### Q: Why does the loading spinner disappear too early? :id=spinner-disappearing

**A**: This was a known issue with some providers (DeepSeek, Perplexity, Ollama) that has been fixed. If you still experience this:

1. **Update to Latest Version**
   - Pull the latest code
   - Restart the server
   
2. **Clear Browser Cache**
   - Hard refresh (Ctrl+F5 or Cmd+Shift+R)
   - Clear site data if needed

3. **Check Provider Status**
   - Some providers may have temporary issues
   - Try switching providers to test

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
- Open multiple browser tabs (experimental)

---

## Need More Help?

- Use **Monadic Help** app for AI-powered assistance
- Check [documentation](/) for detailed guides
- Review [configuration reference](/reference/configuration.md)
- See [quick start tutorial](/getting-started/quick-start.md) for basics