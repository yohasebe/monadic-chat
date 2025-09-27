# AutoForge Architecture Guidelines

## Path and Environment Management

### Use Existing Infrastructure

AutoForge MUST use the existing Monadic Chat infrastructure:

1. **Environment Detection**
   ```ruby
   # Use existing module
   Monadic::Utils::Environment.in_container?
   ```

2. **Path Constants**
   ```ruby
   # Use MonadicApp constants
   MonadicApp::SHARED_VOL        # => "/monadic/data"
   MonadicApp::LOCAL_SHARED_VOL  # => "~/monadic/data" (expanded)
   ```

3. **Path Resolution**
   ```ruby
   # Use Environment module methods
   Monadic::Utils::Environment.data_path  # Returns correct path for environment
   ```

### AutoForge Specific Paths

AutoForge projects should be stored under:
- **Container**: `/monadic/data/auto_forge/`
- **Local**: `~/monadic/data/auto_forge/`

### Required Updates

1. **PathConfig module** should delegate to existing infrastructure
2. **Remove hardcoded paths** like `File.expand_path("~/monadic/data")`
3. **Use MonadicApp constants** where available

### Example Implementation

```ruby
module AutoForge
  module Utils
    module PathConfig
      def base_data_path
        # Use existing infrastructure
        if defined?(MonadicApp::SHARED_VOL)
          Monadic::Utils::Environment.in_container? ?
            MonadicApp::SHARED_VOL :
            MonadicApp::LOCAL_SHARED_VOL
        else
          # Fallback for tests
          Monadic::Utils::Environment.data_path
        end
      end
    end
  end
end
```

## Environment Variables

AutoForge should respect existing ENV variables:
- `IN_CONTAINER` - Override for container detection
- `UI_LANGUAGE` - UI language setting
- `LOG_ROTATE_MAX_BYTES` - Log rotation settings
- `LOG_ROTATE_MAX_FILES` - Log rotation settings

## Integration Points

1. **MonadicApp class** - Base class for all apps
2. **MonadicHelper module** - Common helper methods
3. **StringUtils module** - String manipulation utilities
4. **Monadic::Utils::Environment** - Environment detection and paths

## Testing Considerations

- Mock `Monadic::Utils::Environment.in_container?` in tests
- Use test-specific paths to avoid pollution
- Respect existing test patterns in the codebase

---
*Created: 2025-01-27*