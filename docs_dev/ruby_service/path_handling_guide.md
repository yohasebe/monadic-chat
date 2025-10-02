# Path Handling Guide for Monadic Chat Developers

## Overview

Monadic Chat operates in two distinct environments (local development and Docker production), which creates complexity in file path handling. This guide explains the path abstraction system and best practices for secure file operations.

---

## Three Types of Paths

### 1. **Filesystem Paths** (Ruby Internal)

Used for actual file I/O operations.

- **Development**: `/Users/username/monadic/data/file.txt`
- **Production**: `/monadic/data/file.txt` (inside Docker container)

**Usage:**
```ruby
data_dir = Monadic::Utils::Environment.data_path
file_path = File.join(data_dir, "report.pdf")
File.read(file_path)
```

### 2. **Web URL Paths** (HTML/Frontend)

Used in HTML for browser access to files.

- **Both environments**: `/data/file.txt`

**Usage:**
```ruby
# AI generates HTML with web paths
"<img src='/data/chart.png' />"
"<a href='/data/subdir/report.pdf'>Download</a>"
```

### 3. **AI Prompt Paths** (System Prompts)

Used when instructing AI about file locations.

- **Relative**: `"file.txt"` or `"subdir/file.txt"`
- **User-friendly**: `"the shared folder"`

**Example from system prompt:**
```markdown
Save generated images to the shared folder using only the filename.
Display them with: <img src="/data/FILENAME" />
```

---

## Environment Module

### Core Abstraction

`Monadic::Utils::Environment` provides environment-aware path resolution.

```ruby
module Monadic::Utils::Environment
  # Detect if running inside Docker
  def in_container?
    ENV['IN_CONTAINER'] == 'true' || File.file?("/.dockerenv")
  end

  # Resolve paths based on environment
  def resolve_path(container_path, local_path = nil)
    if in_container?
      container_path
    else
      local_path || container_path.sub('/monadic', File.join(Dir.home, 'monadic'))
    end
  end

  # Standard paths
  def data_path
    resolve_path('/monadic/data')
  end
end
```

### Available Methods

| Method | Development | Production | Purpose |
|--------|-------------|------------|---------|
| `data_path` | `~/monadic/data` | `/monadic/data` | Shared folder |
| `config_path` | `~/monadic/config` | `/monadic/config` | Configuration |
| `log_path` | `~/monadic/log` | `/monadic/log` | Log files |
| `scripts_path` | `~/monadic/data/scripts` | `/monadic/data/scripts` | User scripts |
| `apps_path` | `~/monadic/data/apps` | `/monadic/data/apps` | Custom apps |

---

## Path Validation

### The `validate_file_path` Method

**Location:** `lib/monadic/adapters/read_write_helper.rb`

**Purpose:** Prevent directory traversal attacks and ensure files are within the shared folder.

**Return Values:**
- **Success**: Returns the validated path (string)
- **Failure**: Returns a hash with error details

```ruby
validation_result = validate_file_path(file_path)

if validation_result.is_a?(Hash)
  # Validation failed
  return "Error: #{validation_result[:error]}"
end

# Validation succeeded, proceed with file operation
File.read(file_path)
```

**Error Hash Structure:**
```ruby
{
  error: "Path traversal not allowed",
  path: "../../etc/passwd",
  resolved_path: "/etc/passwd",
  allowed_directory: "/monadic/data"
}
```

### Security Features

1. **Path Traversal Prevention**: Blocks `..` sequences
2. **Symlink Resolution**: Uses `File.realpath` to resolve symbolic links
3. **Boundary Checking**: Ensures resolved path is within `data_path`
4. **Detailed Errors**: Provides debugging information in failure cases

---

## Best Practices

### ✅ DO: Always Use Environment Module

```ruby
# Good
data_dir = Monadic::Utils::Environment.data_path
file_path = File.join(data_dir, filename)

# Bad - hardcoded path
file_path = "/monadic/data/#{filename}"
```

### ✅ DO: Validate Before File Operations

```ruby
def read_file_from_shared_folder(filepath:)
  data_dir = Monadic::Utils::Environment.data_path
  full_path = File.join(data_dir, filepath)

  # ALWAYS validate first
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # Safe to proceed
  File.read(full_path)
end
```

### ✅ DO: Support Subdirectories

```ruby
# Good - supports "projects/report.pdf"
full_path = File.join(data_dir, filepath)

# Bad - only supports root level
full_path = File.join(data_dir, File.basename(filepath))
```

### ✅ DO: Use Web Paths in HTML

```ruby
# Good - works in both environments
"<img src='/data/chart.png' />"

# Bad - environment-specific
"<img src='#{data_dir}/chart.png' />"
```

### ❌ DON'T: Skip Validation

```ruby
# Bad - no validation
def write_file(filepath:, content:)
  File.write(filepath, content)  # UNSAFE!
end
```

### ❌ DON'T: Use File.basename for Security

```ruby
# Bad - prevents subdirectory access
safe_name = File.basename(file_name)
file_path = File.join(data_dir, safe_name)

# Good - validate instead
file_path = File.join(data_dir, file_name)
validation_result = validate_file_path(file_path)
```

---

## Web File Serving

### Sinatra Route: `/data/:file_name`

**Location:** `lib/monadic.rb`

**Functionality:**
- Serves files from shared folder via HTTP
- Supports subdirectories (e.g., `/data/projects/report.pdf`)
- Validates paths to prevent traversal attacks

**Implementation:**
```ruby
get "/data/:file_name" do
  fetch_file(params[:file_name])
end

def fetch_file(file_name)
  datadir = Monadic::Utils::Environment.data_path

  # Normalize and split path
  path_parts = file_name.split('/').reject { |p| p.empty? || p == '.' }

  # Reject path traversal
  if path_parts.any? { |part| part == '..' }
    status 403
    return "Access denied: path traversal not allowed"
  end

  # Construct and validate path
  file_path = File.join(datadir, *path_parts)
  real_path = File.realpath(file_path)
  real_datadir = File.realpath(datadir)

  # Verify within allowed directory
  if real_path.start_with?(real_datadir + File::SEPARATOR) && File.file?(real_path)
    send_file file_path
  else
    status 403
    "Access denied"
  end
end
```

**Security Features:**
1. Rejects `..` in path components
2. Resolves symlinks with `realpath`
3. Verifies final path is within data directory
4. Ensures target is a file (not directory)

---

## Common Patterns

### Pattern 1: Read User File

```ruby
def read_file_from_shared_folder(filepath:)
  data_dir = Monadic::Utils::Environment.data_path

  # Support both absolute and relative paths
  full_path = if filepath.start_with?('/')
                filepath
              else
                File.join(data_dir, filepath)
              end

  # Validate
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # Check existence
  unless File.exist?(full_path)
    return "Error: File not found"
  end

  # Read safely
  File.read(full_path)
rescue StandardError => e
  "Error: #{e.message}"
end
```

### Pattern 2: Write User File

```ruby
def write_file_to_shared_folder(filename:, content:)
  data_dir = Monadic::Utils::Environment.data_path
  full_path = File.join(data_dir, filename)

  # Validate
  validation_result = validate_file_path(full_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # Ensure directory exists
  dir = File.dirname(full_path)
  FileUtils.mkdir_p(dir) unless File.directory?(dir)

  # Write safely
  File.write(full_path, content)

  "File saved: #{filename}"
rescue StandardError => e
  "Error: #{e.message}"
end
```

### Pattern 3: Generate File for AI

```ruby
def generate_chart(data:)
  timestamp = Time.now.to_i
  filename = "chart_#{timestamp}.png"

  data_dir = Monadic::Utils::Environment.data_path
  file_path = File.join(data_dir, filename)

  # Validate
  validation_result = validate_file_path(file_path)
  if validation_result.is_a?(Hash)
    return "Error: #{validation_result[:error]}"
  end

  # Generate chart
  create_chart(data, file_path)

  # Return HTML with web path
  "<img src='/data/#{filename}' />"
end
```

---

## Testing

### Unit Tests

Mock the Environment module:

```ruby
RSpec.describe MyApp do
  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return("/test/data")
  end

  it "validates file paths" do
    result = app.read_file("test.txt")
    expect(result).not_to include("Error")
  end
end
```

### Integration Tests

Test with real paths:

```ruby
RSpec.describe "File operations", :integration do
  let(:data_dir) { Monadic::Utils::Environment.data_path }

  it "reads files from shared folder" do
    test_file = File.join(data_dir, "test.txt")
    File.write(test_file, "test content")

    result = app.read_file("test.txt")
    expect(result).to eq("test content")
  ensure
    File.delete(test_file) if File.exist?(test_file)
  end
end
```

---

## Migration Checklist

When updating existing code:

- [ ] Replace hardcoded `/monadic/data` with `Environment.data_path`
- [ ] Add `validate_file_path` calls before all file operations
- [ ] Update error handling to check for hash return values
- [ ] Support subdirectories (don't use `File.basename` for security)
- [ ] Use `/data/` prefix in HTML output
- [ ] Test in both development and Docker environments
- [ ] Add unit tests for path validation
- [ ] Update system prompts to use relative paths

---

## Debugging

### Enable Debug Logging

```ruby
DebugHelper.debug("File operation: #{file_path}", category: :api, level: :debug)
```

### Check Environment

```ruby
puts "In container: #{Monadic::Utils::Environment.in_container?}"
puts "Data path: #{Monadic::Utils::Environment.data_path}"
```

### Validate Manually

```ruby
result = validate_file_path(file_path)
if result.is_a?(Hash)
  pp result  # Pretty-print error details
end
```

---

## Summary

| Aspect | Development | Production | Best Practice |
|--------|-------------|------------|---------------|
| File I/O | `~/monadic/data/file.txt` | `/monadic/data/file.txt` | Use `Environment.data_path` |
| Web URLs | `/data/file.txt` | `/data/file.txt` | Always use `/data/` prefix |
| Validation | Required | Required | Use `validate_file_path` |
| Subdirs | Supported | Supported | Don't use `File.basename` |
| Security | Path traversal protection | Path traversal protection | Validate before operations |

**Key Takeaway:** Always use `Environment.data_path` and `validate_file_path` for safe, environment-agnostic file operations.