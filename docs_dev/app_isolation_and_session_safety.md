# App Isolation and Session Safety

## Overview

Monadic Chat uses a shared-instance architecture where each app class has a single instance stored in the global `APPS` hash. This design is efficient but requires careful handling of instance variables to prevent cross-session data contamination.

## Architecture

### App Instance Lifecycle

```ruby
# lib/monadic.rb:987-998
def init_apps
  apps = {}
  klass = Object.const_get("MonadicApp")

  klass.subclasses.each do |a|
    app = a.new  # ← Single instance per app class
    # ...
    apps[app_name] = app  # ← Shared across ALL sessions
  end
end

APPS = init_apps  # ← Global constant
```

**Critical Implications**:
- `APPS["Chord Accompanist"]` returns the **same instance** for all users
- Instance variables (`@context`, `@api_key`, `@settings`, etc.) are **shared** across all sessions
- Race conditions can occur when multiple users access the same app simultaneously

### Safe vs Unsafe Patterns

#### ✅ SAFE: Pure Functions (Recommended)

```ruby
class MyApp < MonadicApp
  def my_tool(input:, options:)
    # Uses only parameters - no instance variables
    result = process_input(input, options)

    format_tool_response(
      success: true,
      output: result
    )
  end

  private

  def process_input(input, options)
    # Pure function - same input always produces same output
    # No side effects, no instance variable access
    input.upcase if options[:uppercase]
  end
end
```

**Why Safe**:
- No shared state between invocations
- Thread-safe by design
- No race conditions possible

#### ⚠️ UNSAFE: Instance Variable State

```ruby
class MyApp < MonadicApp
  def validate_code(code:)
    # WRONG: Storing session-specific data in instance variable
    @last_validated_code = code
    @validation_timestamp = Time.now

    # User A's code can be overwritten by User B
    result = validate(code)

    { success: result }
  end

  def preview_code
    # WRONG: Reading shared instance variable
    code = @last_validated_code  # ← May belong to different user!
    generate_preview(code)
  end
end
```

**Why Unsafe**:
- User A calls `validate_code("A's code")`
- User B calls `validate_code("B's code")` → Overwrites `@last_validated_code`
- User A calls `preview_code` → Gets B's code!

## Implemented Safety Measures

### 1. Message Isolation by app_name

**Implementation**: `lib/monadic/utils/websocket.rb:313-315, 523-526, 1163-1169`

```ruby
# Save messages with app_name
new_data = {
  "mid" => SecureRandom.hex(4),
  "role" => "assistant",
  "text" => text,
  "html" => html,
  "app_name" => session["parameters"]["app_name"],  # ← Added
  "active" => true
}
session[:messages] << new_data

# Load messages filtered by app_name
current_app_name = session["parameters"]["app_name"]
messages = session[:messages].filter { |m|
  m["type"] != "search" && m["app_name"] == current_app_name  # ← Filter
}
```

**Protects Against**: Cross-app conversation leakage (e.g., different app instances seeing each other's messages)

### 2. Per-App Embeddings Database

**Implementation**: `lib/monadic/app.rb:162-176`

```ruby
def ensure_embeddings_db
  if @embeddings_db.nil? && defined?(TextEmbeddings)
    # Use per-app database name to avoid cross-app mixing
    app_key = begin
      self.class.name.to_s.strip.downcase.gsub(/[^a-z0-9_\-]/, '_')
    rescue StandardError
      'default'
    end
    base = "monadic_user_docs"
    db_name = "#{base}_#{app_key}"  # ← App-specific DB
    @embeddings_db = TextEmbeddings.new(db_name, recreate_db: false)
  end
  @embeddings_db
end
```

**Protects Against**: Document mixing between apps (e.g., PDF Navigator documents appearing in different app's searches)

### 3. App-Specific System Prompts

**Implementation**: Each app has its own system prompt stored in class settings

```ruby
# Prompt caching uses app-specific system prompts
system_prompt = APPS[app_name].settings["initial_prompt"]
```

**Protects Against**: Prompt cache pollution between apps

## Case Studies

### Case Study 1: Mermaid Grapher (Fixed 2025-01)

**Original Problem**:
```ruby
def run_full_validation(code, source: nil)
  # ...
  @context[:mermaid_last_validation_ok] = true      # ← UNSAFE
  @context[:mermaid_last_validated_code] = code     # ← UNSAFE
end
```

**Issue**:
- User A validates Mermaid code
- User B validates different code → Overwrites `@context`
- User A requests preview → Gets wrong validation state

**Fix** (`apps/mermaid_grapher/mermaid_grapher_tools.rb:314-335`):
```ruby
def run_full_validation(code, source: nil)
  # Removed @context usage entirely
  # Validation workflow now relies on LLM following correct sequence
  result[:validated_code] = code
  result
end
```

### Case Study 2: AutoForge (Fixed 2025-01)

**Original Problem**:
```ruby
def generate_application(params = {})
  context = @context || {}              # ← UNSAFE
  @context ||= context                  # ← UNSAFE

  # Store project info
  @context[:auto_forge] = project_info  # ← UNSAFE
end
```

**Issue**:
- User A creates project "AppA"
- User B creates project "AppB" → Overwrites `@context[:auto_forge]`
- User A's subsequent operations use "AppB" data

**Fix** (`apps/auto_forge/auto_forge_tools.rb:88-94, 201-212`):
```ruby
def generate_application(params = {})
  # Use local variable only
  context = {}                          # ← SAFE

  # Store in local context passed to generators
  context[:auto_forge] = project_info   # ← SAFE (local scope)
  # Removed @context assignment
end
```

## Best Practices for App Development

### DO ✅

1. **Use pure functions for tool methods**
   ```ruby
   def my_tool(input:, param1:, param2:)
     result = process(input, param1, param2)
     format_tool_response(result)
   end
   ```

2. **Pass data through function parameters**
   ```ruby
   def helper_method(data, options)
     # All inputs as parameters
     # Return values, no side effects
   end
   ```

3. **Use Rack session for user-specific state**
   ```ruby
   def my_tool(input:)
     # Thread.current[:rack_session] is session-specific
     session = Thread.current[:rack_session]
     session[:my_app_data] ||= {}
     # Use session storage
   end
   ```

4. **Use filesystem for persistent state**
   ```ruby
   def save_project(project_id:, data:)
     # File-based storage is naturally isolated
     path = File.join(SHARED_VOL, project_id, "state.json")
     File.write(path, JSON.generate(data))
   end
   ```

### DON'T ❌

1. **Never store session-specific data in instance variables**
   ```ruby
   # ❌ WRONG
   def my_tool(input:)
     @user_input = input        # Will be shared!
     @session_id = SecureRandom.hex
   end
   ```

2. **Never rely on instance variable state between tool calls**
   ```ruby
   # ❌ WRONG
   def step1(data:)
     @step1_result = process(data)
   end

   def step2
     use(@step1_result)  # May belong to different user!
   end
   ```

3. **Never use @context for session-specific state**
   ```ruby
   # ❌ WRONG
   def my_tool(input:)
     @context ||= {}
     @context[:user_data] = input
   end
   ```

4. **Never modify @api_key, @settings, or @embeddings_db in tool methods**
   ```ruby
   # ❌ WRONG
   def my_tool(api_key:)
     @api_key = api_key  # Affects all users!
   end
   ```

## Acceptable Uses of Instance Variables

### Read-Only Class Configuration

```ruby
class MyApp < MonadicApp
  def initialize
    super
    @config = load_app_config  # ✅ OK: Read-only, same for all users
  end

  def my_tool(input:)
    # Using @config for read-only settings is fine
    process(input, max_length: @config[:max_length])
  end
end
```

### Per-Request Temporary State (Advanced)

```ruby
def complex_tool(input:)
  # ⚠️ ACCEPTABLE: Instance variable scope limited to single method execution
  # ONLY if you understand Ruby's execution model
  @temp_data = expensive_computation(input)
  result1 = use_temp_data_part1
  result2 = use_temp_data_part2
  @temp_data = nil  # Clean up

  { result1: result1, result2: result2 }
end
```

**Warning**: This pattern is fragile and should be avoided unless necessary for performance.

## Testing for Session Safety

### Manual Testing Checklist

1. **Concurrent User Simulation**:
   - Open two browser windows with different apps
   - Perform operations in alternating sequence
   - Verify no data mixing occurs

2. **State Inspection**:
   - Add debug logging to track instance variable access
   - Monitor for unexpected state changes
   - Check for race conditions

3. **Session Boundary Testing**:
   - Switch between apps in same session
   - Verify messages don't leak
   - Confirm context is properly isolated

### Automated Testing (Future)

```ruby
# spec/integration/app_isolation_spec.rb (example)
RSpec.describe "App Isolation" do
  it "prevents state contamination between concurrent users" do
    # Simulate User A
    session_a = create_session(app: "AppA")
    result_a1 = call_tool(session_a, :my_tool, input: "A's data")

    # Simulate User B
    session_b = create_session(app: "AppA")
    result_b = call_tool(session_b, :my_tool, input: "B's data")

    # User A continues
    result_a2 = call_tool(session_a, :related_tool)

    # Verify no contamination
    expect(result_a2).not_to include("B's data")
  end
end
```

## Summary

**Key Principle**: Treat app instances as **stateless service objects**. All session-specific data must flow through:
- Function parameters (preferred)
- Rack session storage
- Filesystem
- Database

**Never** store session-specific data in instance variables of `MonadicApp` subclasses.

## Related Documentation

- `docs_dev/common-issues.md` - Troubleshooting guide
- `docs_dev/developer/development_workflow.md` - Public developer guidelines
- `lib/monadic/app.rb` - MonadicApp base class
- `lib/monadic/utils/websocket.rb` - Session management
