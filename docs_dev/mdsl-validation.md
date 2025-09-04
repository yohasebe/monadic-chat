# MDSL Validation System

## Overview

The MDSL (Monadic Domain Specific Language) validation system ensures that app definitions are correct and complete before they are loaded into the system.

## Environment Variables

### MDSL_VALIDATION_VERBOSE

Controls the verbosity of MDSL validation output.

- **Default**: `false` (silent mode)
- **Set to `true`**: Shows detailed validation messages using `Kernel.warn`
- **Usage**: `MDSL_VALIDATION_VERBOSE=true rake server:start`

### Validation Levels

1. **Silent Mode** (default)
   - Only critical errors are displayed
   - Validation runs but doesn't output warnings
   - Suitable for production environments

2. **Verbose Mode** (`MDSL_VALIDATION_VERBOSE=true`)
   - All validation warnings are shown
   - Useful for debugging MDSL files
   - Shows missing tool definitions, parameter mismatches, etc.

## Validation Rules

### Required Fields
- `app` - App name must be specified
- `llm` block with `provider` and `model`
- `system_prompt` or `initial_prompt`

### Tool Validation
- All tools referenced in system prompts must have `define_tool` blocks
- Tool parameters must match between definition and usage
- Empty `tools do` blocks are flagged as potential errors

### Provider Validation
- Provider must be one of the supported providers
- Model must be available for the specified provider
- Provider-specific limitations are checked (e.g., Perplexity doesn't support tool calling)

### Naming Conventions
- App name must match the file name pattern
- For provider-specific apps: `AppNameProvider` (e.g., `ChatOpenAI`)
- File name should be `app_name_provider.mdsl`

## Common Validation Errors

### Tool Definition Mismatch
```
Warning: Tool 'analyze_video' is referenced in system_prompt but not defined in tools block
```

### Empty Tools Block
```
Warning: Empty tools block may cause "Maximum function call depth exceeded" errors
```

### Provider Incompatibility
```
Error: Provider 'perplexity' does not support tool calling required by this app
```

## Implementation Details

The validation is performed by `Monadic::Utils::MdslValidator` class which:
1. Parses the MDSL file
2. Checks required fields
3. Validates tool definitions
4. Verifies provider compatibility
5. Reports errors and warnings based on verbosity setting

## Testing MDSL Files

To test an MDSL file with verbose validation:

```bash
MDSL_VALIDATION_VERBOSE=true ruby -r ./docker/services/ruby/lib/monadic.rb -e "
  validator = Monadic::Utils::MdslValidator.new
  validator.validate_file('path/to/app.mdsl')
"
```

## Best Practices

1. Always run validation in verbose mode during development
2. Fix all warnings before deploying to production
3. Keep tool definitions synchronized with system prompts
4. Use consistent naming conventions
5. Test with multiple providers when creating multi-provider apps