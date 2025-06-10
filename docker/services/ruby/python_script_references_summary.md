# Python Script References in Ruby Codebase

## Summary of Python Script Calls

After searching through the Ruby codebase, I found the following Python scripts being called:

### 1. **pdf2txt.py**
- **Location in Python container**: `/monadic/scripts/converters/pdf2txt.py`
- **Called from**:
  - `lib/monadic/app.rb:590` - in `doc2markdown` method
  - `lib/monadic/utils/pdf_text_extractor.rb:42` - in `pdf2text` method
  - `lib/monadic/adapters/read_write_helper.rb:16` - in `fetch_text_from_pdf` method
  - `spec/monadic_app_command_mock.rb:375` - in mock's `doc2markdown` method

### 2. **office2txt.py**
- **Location in Python container**: `/monadic/scripts/converters/office2txt.py`
- **Called from**:
  - `lib/monadic/app.rb:594` - in `doc2markdown` method
  - `lib/monadic/adapters/read_write_helper.rb:4` - in `fetch_text_from_office` method
  - `spec/monadic_app_command_mock.rb:379` - in mock's `doc2markdown` method

### 3. **content_fetcher.py**
- **Location in Python container**: `/monadic/scripts/cli_tools/content_fetcher.py`
- **Called from**:
  - `lib/monadic/app.rb:598` - in `doc2markdown` method
  - `spec/monadic_app_command_mock.rb:383` - in mock's `doc2markdown` method

### 4. **webpage_fetcher.py**
- **Location in Python container**: `/monadic/scripts/cli_tools/webpage_fetcher.py`
- **Called from**:
  - `lib/monadic/app.rb:668` - in `fetch_webpage` method
  - `lib/monadic/adapters/selenium_helper.rb:9` - in `selenium_fetch` method
  - `spec/monadic_app_command_mock.rb:402` - in mock's `fetch_webpage` method

### 5. **extract_frames.py**
- **Location in Python container**: `/monadic/scripts/converters/extract_frames.py`
- **Called from**:
  - `lib/monadic/agents/video_analyze_agent.rb:6` - in `analyze_video` method

### 6. **jupyter_controller.py**
- **Location in Python container**: `/monadic/scripts/services/jupyter_controller.py`
- **Called from**:
  - `lib/monadic/adapters/jupyter_helper.rb:128` - in `add_jupyter_cells` method
  - `lib/monadic/adapters/jupyter_helper.rb:198` - in `create_jupyter_notebook` method

### 7. **run_jupyter.sh**
- **Location in Python container**: `/monadic/scripts/utilities/run_jupyter.sh`
- **Called from**:
  - `lib/monadic/adapters/jupyter_helper.rb:244` - in `run_jupyter` method

## Ruby Scripts Called from Ruby

### 1. **content_fetcher.rb**
- **Called from**:
  - `lib/monadic/adapters/read_write_helper.rb:28` - in `fetch_text_from_file` method

### 2. **video_query.rb**
- **Called from**:
  - `lib/monadic/agents/video_analyze_agent.rb:39` - in `analyze_video` method

### 3. **stt_query.rb**
- **Called from**:
  - `lib/monadic/agents/video_analyze_agent.rb:49` - in `analyze_video` method
  - `lib/monadic/adapters/file_analysis_helper.rb:16` - in `analyze_audio` method

### 4. **image_query.rb**
- **Called from**:
  - `lib/monadic/adapters/file_analysis_helper.rb:9` - in `analyze_image` method

## Path Configuration in Ruby Code

The Ruby code uses specific path configurations for Python scripts:

### In `lib/monadic/app.rb` (lines 346-353):
```ruby
python_script_dirs = [
  "/monadic/scripts",
  "/monadic/scripts/utilities",
  "/monadic/scripts/services",
  "/monadic/scripts/cli_tools",
  "/monadic/scripts/converters",
  "#{USER_SCRIPT_DIR}"
].join(":")
```

This shows that the Ruby code expects Python scripts to be organized in subdirectories under `/monadic/scripts/`.

## Key Observations

1. **All Python scripts are called without path prefixes** - they rely on PATH environment variable being set correctly
2. **The Ruby code adds multiple directories to PATH** when executing Python scripts in the container
3. **Ruby scripts are called from both Ruby and Python containers**
4. **Some files have been moved/reorganized** (e.g., `content_fetcher.rb` was previously a Python script based on the references)

## Action Items for Path Updates

Based on the reorganization visible in the Python scripts directory:
- Python scripts are now organized into subdirectories: `cli_tools/`, `converters/`, `services/`, `utilities/`
- The Ruby code already handles this correctly by adding all subdirectories to PATH
- No Ruby code changes appear to be needed as the scripts are called by name only (not full paths)