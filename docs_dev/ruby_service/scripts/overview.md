# Ruby Service Scripts

The scripts live in `docker/services/ruby/scripts/`.

## Directories

| Path | Contents |
|---|---|
| `cli_tools/` | Command-line tools that the apps call inside the Ruby container |
| `generators/` | Image and video generators |
| `utilities/` | `process_documentation.rb` |
| (top level) | `download_assets.sh`, `ruby-healthcheck.sh`, `mcp_stdio_bridge.rb`, `mcp_client_example.rb` |

### `cli_tools/`

| Script | What it does |
|---|---|
| `content_fetcher.rb <file> [sizecap]` | Prints a file's text (default cap 10 MB) after a binary check |
| `image_query.rb <message> <image path or URL> [model]` | Asks an OpenAI vision model about an image |
| `stt_query.rb <audio> [outdir] [format] [lang] [model]` | OpenAI speech-to-text |
| `tts_query.rb <text file> [--provider=…] [--voice=…] [--speed=…] [--language=…]` | Text-to-speech (OpenAI, Gemini or ElevenLabs); `--list` prints the providers and their voices as JSON |
| `video_query.rb <frames JSON> [query] [model]` | Asks an OpenAI vision model about video frames listed in a JSON file (more than 50 frames are thinned to 50, evenly spaced) |

Default models come from `providerDefaults` in `model_spec.js`.

### `generators/`

`image_generator_openai.rb`, `image_generator_grok.rb`, `video_generator_gemini.rb`, `video_generator_grok.rb`, each using its own provider's API.

### Top Level

- `download_assets.sh`: fetches the web UI's third-party files into `public/vendor` at the versions and hashes in `bin/assets_list.sh`, and builds the maxGraph bundle.
- `ruby-healthcheck.sh`: container healthcheck; succeeds when `http://localhost:4567/` answers.
- `mcp_stdio_bridge.rb`: stdio bridge to the MCP server for stdio-only clients.
- `mcp_client_example.rb`: example MCP client.

### `utilities/process_documentation.rb`

Builds the help database dump `docker/services/ruby/help_data/help_db.json` from `docs/*.md` (and `docs_dev/*.md` with `--include-internal`) using the embeddings service. It does not need Qdrant.
