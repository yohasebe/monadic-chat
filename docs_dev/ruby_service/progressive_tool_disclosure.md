# Progressive Tool Disclosure (PTD)

## Overview

Progressive Tool Disclosure (PTD) is an architectural pattern that dynamically controls tool availability based on runtime conditions. Tools are only visible and accessible when their dependencies are met, improving user experience by preventing errors and confusion.

## Architecture

### Core Components

1. **Shared Tool Groups** (`lib/monadic/shared_tools/`)
   - Reusable collections of related tools
   - Each group has an `available?` class method for runtime checking
   - Tools are defined once and imported by multiple apps

2. **Registry** (`lib/monadic/shared_tools/registry.rb`)
   - Central registry for all shared tool groups
   - Manages visibility rules (`always` or `conditional`)
   - Provides `available?(group)` method for real-time checking

3. **DSL Integration** (`lib/monadic/dsl.rb`)
   - `import_shared_tools` directive for MDSL files
   - Duplicate detection to prevent tool conflicts
   - Metadata tracking for UI display

4. **WebSocket Communication** (`lib/monadic/utils/websocket.rb`)
   - Sends tool group metadata with availability status
   - Real-time updates to web UI

5. **Web UI Display** (`public/js/monadic/utilities.js`)
   - Tool group badges with visibility indicators
   - Conditional rendering based on availability

### Visibility Modes

- **`always`**: Tool group is always available
  - Example: `file_operations`, `python_execution`
  - No runtime checking needed

- **`conditional`**: Tool group availability depends on runtime conditions
  - Example: `web_automation` (requires Selenium container)
  - Checked via `available_when` lambda in registry

## Implementation

### 1. Creating a Shared Tool Group

```ruby
# lib/monadic/shared_tools/example_group.rb
module Monadic
  module SharedTools
    module ExampleGroup
      # Availability check (for conditional visibility)
      def self.available?
        # Check if dependencies are met
        system("docker ps | grep -q example-container")
      end

      # Tool definitions
      TOOLS = [
        {
          type: "function",
          function: {
            name: "example_tool",
            description: "Example tool description",
            parameters: {
              type: "object",
              properties: {
                param1: {
                  type: "string",
                  description: "Parameter description"
                }
              },
              required: ["param1"]
            }
          }
        }
      ].freeze
    end
  end
end
```

### 2. Registering the Tool Group

```ruby
# lib/monadic/shared_tools/registry.rb
TOOL_GROUPS = {
  example_group: {
    module_ref: MonadicSharedTools::ExampleGroup,
    visibility: 'conditional',
    available_when: -> { MonadicSharedTools::ExampleGroup.available? }
  }
}.freeze
```

### 3. Using in MDSL

```ruby
# apps/my_app/my_app_provider.mdsl
MonadicApp.register "MyAppProvider" do
  llm do
    provider "provider_name"
    model "model-name"
  end

  # Import shared tools with conditional visibility
  import_shared_tools :example_group, visibility: "conditional"

  # App-specific tools can still be defined
  tools do
    define_tool "app_specific_tool", "Description" do
      parameter :param1, "string", "Parameter description", required: true
    end
  end
end
```

### 4. Implementing Tool Methods

```ruby
# apps/my_app/my_app_tools.rb
module MyAppTools
  include MonadicHelper
  include MonadicSharedTools::ExampleGroup

  # Tool method implementation
  def example_tool(params)
    # Implementation here
  end
end

class MyAppProvider < MonadicApp
  include ProviderHelper
  include MyAppTools
end
```

## Performance Optimization

### Caching

Tool groups with expensive availability checks should implement caching:

```ruby
module Monadic
  module SharedTools
    module WebAutomation
      @availability_cache ||= { ts: Time.at(0), available: false }

      def self.available?
        # Return cached result if still valid (10 second TTL)
        if (Time.now - @availability_cache[:ts]) <= 10
          return @availability_cache[:available]
        end

        # Perform actual check
        containers = `docker ps --format "{{.Names}}"`
        available = containers.include?("selenium-container")

        # Update cache
        @availability_cache = { ts: Time.now, available: available }
        available
      end
    end
  end
end
```

**Rationale**: Without caching, availability checks run on every app list request. With 7 apps importing the same tool group, this means 7 `docker ps` calls per request. Caching reduces this to 1 call per 10 seconds.

## Existing Tool Groups

### Always Available

1. **`jupyter_operations`** (12 tools)
   - Jupyter notebook management
   - Cell operations, notebook creation

2. **`python_execution`** (4 tools)
   - Code execution in Python container
   - Environment checking

3. **`file_operations`** (3 tools)
   - File write, list, delete
   - Shared folder operations

4. **`file_reading`** (3 tools)
   - Text, PDF, Office file reading
   - Shared folder file access

### Conditionally Available

1. **`web_automation`** (4 tools)
   - Requires: Selenium and Python containers
   - Screenshot capture, web scraping
   - Used by: Visual Web Explorer, AutoForge

2. **`video_analysis_openai`** (1 tool)
   - Requires: OpenAI API key
   - Video content analysis

## Benefits

1. **User Experience**
   - No confusing errors when dependencies are missing
   - Clear indication of unavailable features via UI badges

2. **Code Reuse**
   - Single source of truth for tool definitions
   - Eliminated 92 lines of duplicate code across 7 apps

3. **Maintainability**
   - Tool updates propagate to all apps automatically
   - Consistent error messages and behavior

4. **Scalability**
   - Easy to add new tool groups
   - Simple to add new apps using existing tools

## Migration Guide

### Converting Existing Apps to Use Shared Tools

**Before:**
```ruby
# apps/my_app/my_app_provider.mdsl
tools do
  define_tool "capture_screenshot", "Capture a screenshot" do
    parameter :url, "string", "URL to capture", required: true
  end

  define_tool "scrape_page", "Scrape page content" do
    parameter :url, "string", "URL to scrape", required: true
  end
end
```

**After:**
```ruby
# apps/my_app/my_app_provider.mdsl
import_shared_tools :web_automation, visibility: "conditional"
```

**Tool file changes:**
```ruby
# Before: apps/my_app/my_app_tools.rb
module MyAppTools
  def capture_screenshot(params)
    # Implementation
  end

  def scrape_page(params)
    # Implementation
  end
end

# After: Move implementations to shared module
# lib/monadic/shared_tools/web_automation.rb
module Monadic::SharedTools::WebAutomation
  def capture_screenshot(params)
    # Implementation
  end

  def scrape_page(params)
    # Implementation
  end
end

# apps/my_app/my_app_tools.rb
module MyAppTools
  include MonadicSharedTools::WebAutomation
end
```

## Testing

### Unit Tests

Test tool group availability logic:

```ruby
RSpec.describe "WebAutomation Tool Group" do
  describe ".available?" do
    it "returns true when containers are running" do
      allow_any_instance_of(Kernel).to receive(:`).and_return("selenium-container\npython-container")
      expect(Monadic::SharedTools::WebAutomation.available?).to be true
    end

    it "returns false when containers are missing" do
      allow_any_instance_of(Kernel).to receive(:`).and_return("")
      expect(Monadic::SharedTools::WebAutomation.available?).to be false
    end
  end
end
```

### Integration Tests

Test that unavailable tools return helpful errors:

```ruby
it "provides helpful error when Selenium is unavailable" do
  result = app.capture_screenshot(url: "https://example.com")
  expect(result[:error]).to include("Selenium container is not running")
  expect(result[:suggestion]).to include("start the Selenium container")
end
```

## Future Enhancements

1. **Dynamic Tool Loading**
   - Load tool groups only when needed
   - Reduce memory footprint for apps with many conditional tools

2. **User Preferences**
   - Allow users to disable specific tool groups
   - Custom tool group visibility settings

3. **Dependency Chain Detection**
   - Automatically check transitive dependencies
   - Warn when tool groups depend on each other

4. **Health Monitoring**
   - Periodic availability checks in background
   - Proactive notifications when dependencies become unavailable

## Related Documentation

- `docs_dev/developer/code_structure.md` - Overall architecture
- `docs/advanced-topics/monadic_dsl.md` - MDSL syntax reference
- `docs_dev/ruby_service/gemini_tool_continuation_fix.md` - Tool format handling
