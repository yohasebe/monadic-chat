# Monadic Chat Scripts

This directory contains various utility scripts to help with Monadic Chat development and operations.

## Directory Structure

### `/utilities/`
General utility scripts needed for build and setup
- `download_assets.sh` - Download required assets (CSS, JS, fonts, etc.)
- `fix_font_awesome_paths.sh` - Fix Font Awesome paths

### `/cli_tools/`
Various tools that can be executed directly from command line
- `content_fetcher.rb` - Read file contents and perform binary checks
- `image_query.rb` - Base64 encode images and query OpenAI API
- `stt_query.rb` - Speech-to-Text transcription from audio files
- `tts_query.rb` - Text-to-Speech generation
- `video_query.rb` - Video file analysis and frame extraction

### `/generators/`
Standalone tools for content generation
- `image_generator_grok.rb` - Image generation using Grok API
- `image_generator_openai.rb` - Image generation using OpenAI DALL-E API
- `video_generator_veo.rb` - Video generation using Google Veo API

### `/diagnostics/`
Diagnostic and testing scripts for various features
- `/apps/concept_visualizer/` - Diagnostic tools for Concept Visualizer app
- `/apps/wikipedia/` - Testing tools for Wikipedia functionality

## Usage

### CLI Tools Examples

```bash
# Fetch file contents (up to 10MB)
ruby scripts/cli_tools/content_fetcher.rb /path/to/file.txt

# Ask questions about an image
ruby scripts/cli_tools/image_query.rb /path/to/image.png "What is in this image?"

# Transcribe audio to text
ruby scripts/cli_tools/stt_query.rb /path/to/audio.mp3
```

### Diagnostic Tools Examples

```bash
# Test Concept Visualizer basic functionality
cd scripts/diagnostics/apps/concept_visualizer/
./test_concept_visualizer_simple.sh

# Test Wikipedia loading
ruby scripts/diagnostics/apps/wikipedia/test_wikipedia_loading.rb
```

## Notes

- Many scripts require API key configuration (e.g., `OPENAI_API_KEY`)
- Diagnostic scripts should be run with Docker containers running
- CLI tools operate independently but require necessary dependencies to be installed
