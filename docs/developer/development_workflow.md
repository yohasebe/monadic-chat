# Development Workflow

This document contains guidelines and instructions for developers contributing to the Monadic Chat project.

?> This document is for developers of Monadic Chat itself, not for developers of Monadic Chat applications.

## Testing

### Test Frameworks
- **JavaScript**: Uses Jest for frontend code testing
- **Ruby**: Uses RSpec for backend code testing

### Test Structure
- JavaScript tests are in `test/frontend/`
- Ruby tests are in `docker/services/ruby/spec/`
- Jest configuration in `jest.config.js`
- Global test setup for JavaScript in `test/setup.js`

### Running Tests
#### Ruby Tests
```bash
rake spec
```

#### JavaScript Tests
```bash
rake jstest        # Run passing JavaScript tests
npm test           # Same as above
rake jstest_all    # Run all JavaScript tests
npm run test:watch # Run tests in watch mode
npm run test:coverage # Run tests with coverage report
```

#### All Tests
```bash
rake test  # Run both Ruby and JavaScript tests
```

## MDSL Development Tools

### CLI Tool: mdsl_tool_completer

The `mdsl_tool_completer` is a command-line tool for testing and validating MDSL auto-completion functionality. It helps developers preview and debug tool auto-completion for MDSL applications.

#### Location
```bash
docker/services/ruby/bin/mdsl_tool_completer
```

#### Usage

**Basic Preview:**
```bash
# Preview auto-completion for a specific app
ruby bin/mdsl_tool_completer novel_writer
ruby bin/mdsl_tool_completer drawio_grapher
```

**Validation Mode:**
```bash
# Validate tool consistency between definitions and implementations
ruby bin/mdsl_tool_completer --action validate app_name
ruby bin/mdsl_tool_completer --action validate novel_writer
```

**Analysis Mode:**
```bash
# Detailed analysis with verbose output
ruby bin/mdsl_tool_completer --action analyze app_name
ruby bin/mdsl_tool_completer --action analyze --verbose novel_writer
```

**All Apps Analysis:**
```bash
# Analyze all apps in the system
ruby bin/mdsl_tool_completer --action analyze --all
```

#### Command Options

- `--action validate`: Check tool implementation consistency
- `--action analyze`: Perform detailed method analysis
- `--verbose`: Enable detailed output for analysis
- `--all`: Process all available apps
- `--help`: Display usage information

#### Example Output

**Preview Mode:**
```bash
$ ruby bin/mdsl_tool_completer novel_writer

=== MDSL Tool Completer ===
App: novel_writer
Tools file: /path/to/novel_writer_tools.rb

Auto-completed tools:
- count_num_of_words (text: string)
- count_num_of_characters (text: string)
- save_content_to_file (content: string, filename: string)

Total methods found: 3
```

**Validation Mode:**
```bash
$ ruby bin/mdsl_tool_completer --action validate novel_writer

=== Tool Implementation Validation ===
✓ count_num_of_words: Implementation found
✓ count_num_of_characters: Implementation found  
✓ save_content_to_file: Implementation found

All tools have valid implementations.
```

#### Environment Variables

The tool respects the unified debug system:
- `MONADIC_DEBUG=mdsl`: Enable MDSL debug output
- `MONADIC_DEBUG_LEVEL=debug`: Set debug verbosity level

Legacy variables (still supported but deprecated):
- `MDSL_AUTO_COMPLETE=debug`: Enable MDSL debug output
- `APP_DEBUG=1`: Enable general debug output

## Debug System

Monadic Chat uses a unified debug system controlled via environment variables:

### Debug Categories
- `all`: All debug messages
- `app`: General application debugging
- `embeddings`: Text embeddings operations
- `mdsl`: MDSL tool completion
- `tts`: Text-to-Speech operations
- `drawio`: DrawIO grapher operations
- `ai_user`: AI user agent
- `web_search`: Web search operations (includes Tavily)
- `api`: API requests and responses

### Debug Levels
- `none`: No debug output (default)
- `error`: Only errors
- `warning`: Errors and warnings
- `info`: General information
- `debug`: Detailed debug information
- `verbose`: Everything including raw data

### Error Handling Improvements
- **Error Pattern Detection**: System automatically detects repeated errors and stops after 3 similar occurrences
- **UTF-8 Encoding**: All responses are properly handled with fallback encoding replacement
- **Infinite Loop Prevention**: Tool calls are limited to prevent "Maximum function call depth exceeded" errors
- **Graceful Degradation**: Missing API keys result in clear error messages, not crashes

### Usage Examples
```bash
# Enable web search debug output
export MONADIC_DEBUG=web_search
export MONADIC_DEBUG_LEVEL=debug

# Enable multiple categories
export MONADIC_DEBUG=api,web_search,mdsl

# Enable all debug output
export MONADIC_DEBUG=all
export MONADIC_DEBUG_LEVEL=verbose

# API debugging (equivalent to Electron's "Extra Logging")
export MONADIC_DEBUG=api
```

### MDSL Development Best Practices

#### File Structure
Monadic Chat applications now use the MDSL (Monadic Domain Specific Language) format exclusively:

- **App Definition**: `app_name_provider.mdsl` (e.g., `chat_openai.mdsl`)
- **Tool Implementation**: `app_name_tools.rb` (e.g., `chat_tools.rb`)
- **Shared Constants**: `app_name_constants.rb` (optional)

#### Tool Implementation Pattern

When developing MDSL applications, always implement the facade pattern for custom tools:

```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  def custom_method(param:, options: {})
    # 1. Input validation
    raise ArgumentError, "Parameter required" if param.nil?
    
    # 2. Call underlying implementation
    result = perform_operation(param, options)
    
    # 3. Return structured response
    { success: true, data: result }
  rescue StandardError => e
    { success: false, error: e.message }
  end
end
```

#### Empty Tools Block Issue

**Important**: Empty `tools do` blocks in MDSL files can cause "Maximum function call depth exceeded" errors. Always either:

1. **Define tools explicitly** in the MDSL file:
```ruby
tools do
  define_tool "fetch_text_from_pdf", "Extract text from PDF" do
    parameter :pdf, "string", "PDF filename", required: true
  end
end
```

2. **Create a companion tools file** that inherits standard tools:
```ruby
# app_name_tools.rb
class AppNameProvider < MonadicApp
  # Inherits standard tools from MonadicApp
end
```

#### Common Development Issues

**Missing Method Errors:**
- Symptom: `undefined method 'method_name' for an instance of AppName`
- Solution: Create facade methods in `*_tools.rb` file with proper validation

**Maximum function call depth exceeded:**
- Symptom: Error when running app with empty `tools do` block
- Solution: Add explicit tool definitions or create `*_tools.rb` file

**Tool Implementation Validation:**
```bash
# Check if your tools are properly defined
ruby bin/mdsl_tool_completer --action validate your_app_name
```

**Auto-completion Debugging:**
```bash
# Preview what tools will be auto-completed
ruby bin/mdsl_tool_completer your_app_name

# Debug auto-completion issues (new unified system)
export MONADIC_DEBUG=mdsl
export MONADIC_DEBUG_LEVEL=debug
ruby bin/mdsl_tool_completer your_app_name

# Or using legacy method (deprecated)
export MDSL_AUTO_COMPLETE=debug
ruby bin/mdsl_tool_completer your_app_name
```

#### Provider-Specific Considerations

- **Function Limits**: OpenAI/Gemini support up to 20 function calls, Claude supports up to 16
- **Code Execution**: All providers now use `run_code` (previously Anthropic used `run_script`)
- **Array Parameters**: OpenAI requires `items` property for array parameters
## MDSL Auto-Completion Control

The MDSL auto-completion system can be controlled using environment variables:

```bash
# Disable auto-completion (useful when debugging MDSL files)
export MDSL_AUTO_COMPLETE=false

# Enable with detailed debug logging
export MDSL_AUTO_COMPLETE=debug

# Enable normally (default)
export MDSL_AUTO_COMPLETE=true
# or just unset the variable
unset MDSL_AUTO_COMPLETE
```

## Important: Managing Setup Scripts

The `pysetup.sh` and `rbsetup.sh` files located in `docker/services/python/` and `docker/services/ruby/` are replaced during container build with files that users might place in the `config` directory of the shared folder to install additional packages. You should always commit the original versions of these scripts to the version control system (Git). Before committing changes to the repository, reset these files using one of the methods below:

#### Method 1: Using the Reset Script

Run the provided reset script:

```bash
./docker/services/reset_setup_scripts.sh
```

This will restore the original versions of the setup scripts from git.

#### Method 2: Manual Reset

Alternatively, you can manually reset the files using git:

```bash
git checkout -- docker/services/python/pysetup.sh docker/services/ruby/rbsetup.sh
```

### Git Pre-commit Hook (Optional)

You can set up a git pre-commit hook to automatically reset these files before each commit:

1. Create a file named `pre-commit` in your `.git/hooks/` directory:

```bash
touch .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

2. Add the following content to the pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit - Automatically reset setup scripts before commit

# Get the files that are staged for commit
STAGED_FILES=$(git diff --cached --name-only)

# Check if our setup scripts are modified
if echo "$STAGED_FILES" | grep -q "docker/services/python/pysetup.sh\|docker/services/ruby/rbsetup.sh"; then
  echo "⚠️ Setup script changes detected in commit."
  echo "⚠️ Resetting to original versions from git..."
  
  # Reset them
  git checkout -- docker/services/python/pysetup.sh
  git checkout -- docker/services/ruby/rbsetup.sh
  
  # Re-add them to staging
  git add docker/services/python/pysetup.sh
  git add docker/services/ruby/rbsetup.sh
  
  echo "✅ Setup scripts reset. Proceeding with commit."
fi

# Allow the commit to proceed
exit 0
```

This pre-commit hook will automatically detect and reset any changes to the setup scripts before committing.

## For Users

Users who want to customize their containers should place custom scripts in:
- `~/monadic/config/pysetup.sh` for Python customizations
- `~/monadic/config/rbsetup.sh` for Ruby customizations

These will be automatically used when building containers locally, but won't affect the repository files.