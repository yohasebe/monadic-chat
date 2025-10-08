# Model Alias and Version Filtering System

## Overview

Monadic Chat implements a sophisticated model alias and version filtering system that:
- Reduces duplication in `model_spec.js` by using model name aliasing
- Automatically resolves dated model names to their base specifications
- Filters model lists to show only relevant versions in the Web UI
- Supports multiple date formats across different AI providers

## Architecture

### Three-Layer System

1. **model_spec.js (Specification Layer)**
   - Contains base model specifications (usually dateless versions)
   - May include dated versions when specifications differ
   - Single source of truth for model capabilities

2. **Provider API Layer**
   - Fetches available models from each provider's API
   - Returns actual model names that can be used
   - May include both dated and dateless versions

3. **Display Layer (Web UI)**
   - Filters and displays models to users
   - Shows dateless version + latest dated version for each base model
   - Only displays models that exist in the provider's API response

## Model Name Normalization

### Supported Date Formats

The system recognizes and parses seven date formats:

| Format | Example | Provider | Notes |
|--------|---------|----------|-------|
| `YYYY-MM-DD` | `gpt-4o-2024-11-20` | OpenAI, xAI | Most common format |
| `YYYYMMDD` | `claude-3-7-sonnet-20250219` | Claude | 8-digit date |
| `MM-YYYY` | `command-r7b-12-2024` | Cohere | Month-year format |
| `YYMM` | `magistral-small-2509` | Mistral | 2-digit year + month (2509 = Sep 2025) |
| `MM-DD` | `gemini-2.5-flash-lite-06-17` | Gemini | Month-day format |
| `exp-MMDD` | `gemini-2.0-flash-thinking-exp-1219` | Gemini | Experimental builds |
| `-NNN` | `gemini-2.0-flash-001` | Gemini | Sequential version numbers |

### Date Validation

The system validates date suffixes to distinguish them from version numbers:

```javascript
// Valid date: passes validation
magistral-small-2509  // YYMM: 25 (2025) is valid year, 09 (Sep) is valid month

// Not a date: fails validation
gpt-4.1               // 4.1 is a version number, not a date
c4ai-aya-vision-32b   // 32b is parameter size, not a date
```

Validation rules:
- Year range: 2020-2030
- Month range: 1-12
- Day range: 1-31

## Alias Resolution Process

### Ruby Side

```ruby
# 1. Normalize model name (remove date suffix)
normalize_model_name("gpt-5-2025-08-07")  # => "gpt-5"

# 2. Resolve alias (fallback to base model if dated version not in spec)
resolve_model_alias("gpt-5-2025-08-07")   # => "gpt-5"

# 3. Get specification (automatically uses resolved name)
get_model_spec("gpt-5-2025-08-07")        # => spec for "gpt-5"
```

**Implementation**: `docker/services/ruby/lib/monadic/utils/model_spec.rb`

### JavaScript Side

```javascript
// 1. Extract date information
extractDateSuffix("gpt-5-2025-08-07")
// => { dateString: "2025-08-07", parsedDate: Date, format: "YYYY-MM-DD" }

// 2. Get base model name
getBaseModelName("gpt-5-2025-08-07")  // => "gpt-5"

// 3. Filter to latest versions
filterToLatestVersions(["gpt-5", "gpt-5-2025-08-07", "gpt-5-2024-01-01"])
// => ["gpt-5", "gpt-5-2025-08-07"]
```

**Implementation**: `docker/services/ruby/public/js/monadic/model_utils.js`

## Display Logic

### Web UI Model List Generation

The Web UI displays models based on what the provider's API returns:

```
Provider API returns: ["gpt-5", "gpt-5-2025-08-07", "gpt-5-2024-01-01"]
                              ↓
                    filterToLatestVersions()
                              ↓
Display in Web UI:   ["gpt-5", "gpt-5-2025-08-07"]
```

### Filtering Rules

For each base model (e.g., `gpt-5`):

1. **No dated versions**: Show dateless version only
   - Input: `["gpt-5"]`
   - Output: `["gpt-5"]`

2. **Dated versions only**: Show latest dated version only
   - Input: `["gpt-5-2024-01-01", "gpt-5-2025-08-07"]`
   - Output: `["gpt-5-2025-08-07"]`

3. **Both dateless and dated**: Show both dateless + latest dated
   - Input: `["gpt-5", "gpt-5-2024-01-01", "gpt-5-2025-08-07"]`
   - Output: `["gpt-5", "gpt-5-2025-08-07"]`

### Date Sorting

Models are sorted by actual date value, not string comparison:

```javascript
// Correct sorting using parsed dates
["command-r-08-2024", "command-r-03-2025", "command-r-12-2024"]
  => Latest: "command-r-03-2025" (March 2025 is newest)

// String sorting would incorrectly give: "command-r-12-2024"
```

## Provider-Specific Behavior

### OpenAI Example

**API Response**: Only returns `gpt-5` (dateless)

**model_spec.js**: Contains `gpt-5` specification

**Web UI**: Displays only `gpt-5`

**Direct Use**: Can specify `gpt-5-2025-08-07` in MDSL, OpenAI treats it as `gpt-5`

### Claude Example

**API Response**: Returns `claude-3-7-sonnet-20250219` (dated only)

**model_spec.js**: Contains `claude-3-7-sonnet-20250219` specification

**Web UI**: Displays `claude-3-7-sonnet-20250219`

**Note**: Claude models typically only have dated versions

## Benefits

### Reduced Duplication

Before:
```javascript
"gpt-5": { /* 13 properties */ },
"gpt-5-2025-08-07": { /* same 13 properties */ }
```

After:
```javascript
"gpt-5": { /* 13 properties */ }
// gpt-5-2025-08-07 automatically resolves to gpt-5
```

**Result**: ~13% reduction in `model_spec.js` size

### Automatic Updates

When provider adds new dated version:
- Provider API returns new version (e.g., `gpt-5-2025-12-01`)
- Web UI automatically displays it alongside `gpt-5`
- Uses existing `gpt-5` specification via alias resolution
- No manual update to `model_spec.js` needed

### User Flexibility

Users can:
- Select dateless version for stable API
- Select latest dated version for newest features
- Specify old dated versions in MDSL (automatically falls back to base spec)

## Edge Cases

### Different Specifications

When dated and dateless versions have different specs, both are kept in `model_spec.js`:

```javascript
"gpt-4o": {
  "max_output_tokens": [1, 16384]
  // ...
},
"gpt-4o-2024-05-13": {
  "max_output_tokens": [1, 4096]  // Different!
  // ...
}
```

Both will appear in Web UI because their specifications differ.

### Version Numbers vs. Dates

The system correctly distinguishes:

```
gpt-4.1              => NOT a date (version number)
gemini-2.0-flash-001 => Date (NNN format)
command-r7b-12-2024  => 7b is ignored, 12-2024 is date (MM-YYYY)
```

## Testing

### Ruby Tests

```bash
cd docker/services/ruby
bundle exec ruby -e "
require_relative 'lib/monadic/utils/model_spec'

# Test normalization
puts Monadic::Utils::ModelSpec.normalize_model_name('gpt-5-2025-08-07')
# => gpt-5

# Test alias resolution
puts Monadic::Utils::ModelSpec.resolve_model_alias('gpt-5-2025-08-07')
# => gpt-5
"
```

### JavaScript Tests

```javascript
// Test date extraction
extractDateSuffix('magistral-small-2509')
// => { dateString: "2509", parsedDate: Date(2025-09-01), format: "YYMM" }

// Test filtering
filterToLatestVersions(['gpt-5', 'gpt-5-2025-08-07', 'gpt-5-2024-01-01'])
// => ['gpt-5', 'gpt-5-2025-08-07']
```

## Maintenance

### Adding New Date Format

1. Add pattern matching to `extractDateSuffix()` in JavaScript
2. Add corresponding case to `getBaseModelName()` switch statement
3. Add pattern matching to `normalize_model_name()` in Ruby
4. Test with representative model names

### Updating model_spec.js

**When to keep dated version**:
- Specifications differ from dateless version
- Only dated version exists (no dateless equivalent)

**When to remove dated version**:
- Specifications match dateless version exactly
- Dateless version exists in spec

## Related Files

- `docker/services/ruby/lib/monadic/utils/model_spec.rb` - Ruby normalization and alias resolution
- `docker/services/ruby/public/js/monadic/model_utils.js` - JavaScript filtering and date parsing
- `docker/services/ruby/public/js/monadic/model_spec.js` - Model specifications
- `docker/services/ruby/lib/monadic/utils/provider_model_cache.rb` - API model fetching with fallback
- `docs/developer/model_spec_vocabulary.md` - Model capability vocabulary (SSOT)
