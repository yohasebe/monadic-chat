# Development Workflow

This document contains guidelines and instructions for developers contributing to the Monadic Chat project.

?> This document is for developers of Monadic Chat itself, not for developers of Monadic Chat applications.

## Testing :id=testing

### Test Frameworks :id=test-frameworks
- **JavaScript**: Uses Jest for frontend code testing
- **Ruby**: Uses RSpec for backend code testing

### Test Structure :id=test-structure
- JavaScript tests are in `test/frontend/`
- Ruby tests are in `docker/services/ruby/spec/`
- App-specific diagnostic scripts are in `docker/services/ruby/scripts/diagnostics/apps/{app_name}/`
- Jest configuration in `jest.config.js`
- Global test setup for JavaScript in `test/setup.js`

### App-Specific Test Scripts :id=app-specific-test-scripts
For applications that require specific testing or diagnosis:
- Place test scripts in the diagnostics directory: `docker/services/ruby/scripts/diagnostics/apps/{app_name}/`
- Use descriptive names: `test_feature_name.sh` or `diagnose_issue.rb`
- Avoid placing app-specific test scripts in the project root directory
- Example: Concept Visualizer test scripts are in `docker/services/ruby/scripts/diagnostics/apps/concept_visualizer/`

!> **Important:** Test scripts should NOT be placed in `apps/{app_name}/test/` directories, as files in `test/` subdirectories within apps are ignored during app loading to prevent test scripts from being loaded as applications.

### Running Tests :id=running-tests

?> **Note:** When using `rake server:debug` for development, Ruby tests run directly on the host using your local Ruby environment.

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

## Debug System :id=debug-system

Monadic Chat uses a unified debug system controlled via configuration variables in `~/monadic/config/env`:

### Debug Categories :id=debug-categories
- `all`: All debug messages
- `app`: General application debugging
- `embeddings`: Text embeddings operations
- `tts`: Text-to-Speech operations
- `drawio`: DrawIO grapher operations
- `ai_user`: AI user agent
- `web_search`: Web search operations (includes Tavily)
- `api`: API requests and responses

### Debug Levels :id=debug-levels
- `none`: No debug output (default)
- `error`: Only errors
- `warning`: Errors and warnings
- `info`: General information
- `debug`: Detailed debug information
- `verbose`: Everything including raw data

### Usage Examples :id=debug-usage-examples

Add these settings to your `~/monadic/config/env` file:

```
# Enable web search debug output
MONADIC_DEBUG=web_search
MONADIC_DEBUG_LEVEL=debug

# Enable multiple categories
MONADIC_DEBUG=api,web_search,mdsl

# Enable all debug output
MONADIC_DEBUG=all
MONADIC_DEBUG_LEVEL=verbose

# API debugging (equivalent to Electron's "Extra Logging")
MONADIC_DEBUG=api
```

### Error Handling Improvements :id=error-handling-improvements
- **Error Pattern Detection**: System automatically detects repeated errors and stops after 3 similar occurrences
- **UTF-8 Encoding**: All responses are properly handled with fallback encoding replacement
- **Infinite Loop Prevention**: Tool calls are limited to prevent "Maximum function call depth exceeded" errors
- **Graceful Degradation**: Missing API keys result in clear error messages, not crashes

### Usage Examples :id=setup-usage-examples

Add these settings to your `~/monadic/config/env` file:

```
# Enable web search debug output
MONADIC_DEBUG=web_search
MONADIC_DEBUG_LEVEL=debug

# Enable multiple categories
MONADIC_DEBUG=api,web_search,mdsl

# Enable all debug output
MONADIC_DEBUG=all
MONADIC_DEBUG_LEVEL=verbose

# API debugging (equivalent to Electron's "Extra Logging")
MONADIC_DEBUG=api
```

## MDSL Development Tools :id=mdsl-development-tools

### MDSL Auto-Completion System (Experimental) :id=mdsl-auto-completion-system

!> **Warning:** This is an experimental feature and may be changed or removed in future versions.

The MDSL auto-completion system aims to solve the development challenge of synchronizing tool definitions between Ruby implementations and MDSL declarations.

#### Problem It Solves :id=problem-solved

Monadic Chat apps require:
1. Implementing tool methods in Ruby (`*_tools.rb` files)
2. Declaring tools in MDSL for LLM recognition (`*.mdsl` files)

Without auto-completion, you must manually duplicate all method signatures, which is:
- Time-consuming and error-prone
- Difficult to maintain when parameters change
- Easy to forget, leaving tools unavailable to the LLM

#### How It Works :id=how-it-works

When enabled, the system automatically:
1. **Detects** Ruby methods in `*_tools.rb` files
2. **Analyzes** method signatures and infers parameter types
3. **Generates** corresponding MDSL tool definitions
4. **Updates** MDSL files with missing definitions

#### Example :id=auto-completion-example

Write this Ruby method:
```ruby
# novel_writer_tools.rb
def count_num_of_words(text: "")
  text.split.size
end
```

System automatically generates this MDSL definition:
```ruby
# novel_writer_openai.mdsl
define_tool "count_num_of_words", "Count the num of words" do
  parameter :text, "string", "The text content to process"
end
```

#### Controlling Auto-Completion :id=controlling-auto-completion

Configure in `~/monadic/config/env` file:
```
# Disabled (default) - tools work at runtime but MDSL files aren't modified
MDSL_AUTO_COMPLETE=false

# Enabled - automatically update MDSL files with missing tool definitions
MDSL_AUTO_COMPLETE=true

# Debug mode - same as enabled but with verbose logging
MDSL_AUTO_COMPLETE=debug
```

#### Important Notes :id=auto-completion-notes

- **Experimental feature**: Still in development and may behave unexpectedly
- **Default is OFF**: Must explicitly enable to modify MDSL files
- **Runtime vs Build-time**: Tools are available at runtime even when disabled
- **Backup files**: Creates backups before modifying MDSL files
- **Standard tools**: Automatically excludes tools inherited from MonadicApp
- **Smart detection**: Only processes public methods with tool-like signatures

#### Known Limitations :id=auto-completion-limitations

- May not correctly infer complex parameter types
- Could overwrite manual customizations
- Affects app loading performance when enabled
- Not recommended for production use

### MDSL Development Best Practices :id=mdsl-best-practices

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


**Debugging Auto-completion:**
1. Add the following to your `~/monadic/config/env` file:
```
# Enable auto-completion with debug output
MDSL_AUTO_COMPLETE=debug
```

2. Start the server and load apps:
```bash
rake server:start
```

3. Check console output for auto-completion messages

**Manual Tool Verification:**
```bash
# Check if tools are properly implemented in Ruby
grep -n "def " apps/your_app/your_app_tools.rb

# Verify tool definitions in MDSL
grep -A5 "tools do" apps/your_app/your_app_provider.mdsl
```

#### Provider-Specific Considerations :id=provider-considerations

- **Function Limits**: OpenAI/Gemini support up to 20 function calls, Claude supports up to 16
- **Code Execution**: All providers use `run_code` for code execution
- **Array Parameters**: OpenAI requires `items` property for array parameters

## Important: Managing Setup Scripts :id=managing-setup-scripts

The `pysetup.sh` and `rbsetup.sh` files in the repository are placeholder scripts that get replaced during container build with user-provided versions from `~/monadic/config/`. Always commit the original placeholder versions to Git. Before committing changes, reset these files using one of the methods below:

Note: The `olsetup.sh` script is only created by users in `~/monadic/config/` for Ollama model installation and has no placeholder version in the repository.

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

### Git Pre-commit Hook (Optional) :id=git-precommit-hook

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

## Development Environment Setup :id=development-environment-setup

### Running Monadic Chat for Development :id=running-for-development

For development purposes, you can run Monadic Chat without the Electron app:

```bash
rake server:debug
```

This command:
- Starts the server in debug mode with `EXTRA_LOGGING=true`
- Does NOT start the Ruby container - uses host Ruby runtime instead
- Starts all other containers (Python, PostgreSQL, pgvector, Ollama if available)
- Uses files from `/docker/services/ruby/` directly on the host
- Makes the web UI accessible via browser at `http://localhost:4567`

This setup allows you to:
- Edit Ruby code and see changes immediately without rebuilding containers
- Use your local Ruby development tools (debuggers, linters, etc.)
- Test changes quickly in the browser interface
- Keep other required services running in containers

### Local Development with Containers :id=local-development-containers
When developing locally while using container features:
- **Ruby container**: Can be stopped to use local Ruby environment
- **Other containers**: Must remain running for apps that depend on them
- **Python container**: Required for apps like Concept Visualizer and Syntax Tree that use LaTeX
- **Paths**: Automatically adjusted via `IN_CONTAINER` constant (automatically set based on container detection)

### Testing Apps with Container Dependencies :id=testing-container-dependencies
For apps that require specific containers (e.g., Concept Visualizer needs Python container for LaTeX):
1. Ensure required containers are running: `./docker/monadic.sh check`
2. If developing locally, stop only the Ruby container
3. Run your local Ruby code - it will communicate with other running containers
4. Container paths (`/monadic/data`) are automatically mapped to host paths (`~/monadic/data`)

### Docker Compose Project Consistency :id=docker-compose-consistency
When working with Docker Compose commands, always use the project name flag to ensure consistency:
```bash
docker compose -p "monadic-chat" [command]
```
This is especially important for packaged Electron apps to maintain proper container management.

### MDSL Auto-Completion Control :id=mdsl-auto-completion-control-section

MDSL auto-completion system can be controlled via configuration variables. Configure in `~/monadic/config/env` file:

```
# Disable auto-completion (useful when debugging MDSL files)
MDSL_AUTO_COMPLETE=false

# Enable with verbose debug logging
MDSL_AUTO_COMPLETE=debug

# Enable normally
MDSL_AUTO_COMPLETE=true

# Default behavior (auto-completion is disabled)
# MDSL_AUTO_COMPLETE is unset or defaults to false
```

## For Users :id=for-users

Users who want to customize their containers should place custom scripts in:
- `~/monadic/config/pysetup.sh` for Python customizations
- `~/monadic/config/rbsetup.sh` for Ruby customizations
- `~/monadic/config/olsetup.sh` for Ollama model installations

These user-provided scripts will be automatically used when building containers locally, replacing the placeholder scripts during the build process. However, they won't be committed to the Git repository.