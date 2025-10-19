# Internal Documentation Support for Monadic Help

## Overview

The Monadic Help system supports both external (public) and internal (developer-only) documentation through the `is_internal` flag. This feature enables developers to search internal technical documentation (`docs_dev/`) alongside public user documentation (`docs/`) during development, while ensuring internal docs never appear in distribution packages.

## Architecture

### Database Schema

Both `help_docs` and `help_items` tables include an `is_internal` boolean column:

```sql
CREATE TABLE help_docs (
  ...
  is_internal BOOLEAN DEFAULT FALSE,
  ...
);

CREATE TABLE help_items (
  ...
  is_internal BOOLEAN DEFAULT FALSE,
  ...
);

-- Indexes for efficient filtering
CREATE INDEX idx_help_docs_is_internal ON help_docs(is_internal);
CREATE INDEX idx_help_items_is_internal ON help_items(is_internal);
```

### Data Flow

```
┌─────────────────────────────────────────────────────┐
│ Development (DEBUG_MODE=true)                       │
├─────────────────────────────────────────────────────┤
│ docs/ (45 files) → is_internal=false               │
│ docs_dev/ (154 files) → is_internal=true           │
│                                                      │
│ Database: 199 total documents                       │
│ Search: Returns both external + internal            │
│ Export: N/A (not exported in DEBUG_MODE)            │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ Production (rake build)                              │
├─────────────────────────────────────────────────────┤
│ docs/ (45 files) → is_internal=false               │
│                                                      │
│ Database: 45 external documents only                │
│ Search: Returns only external docs                  │
│ Export: Only is_internal=false entries              │
└─────────────────────────────────────────────────────┘
```

## Usage

### For Developers

#### 1. Building Help Database with Internal Docs

```bash
# Option 1: Use DEBUG_MODE (automatic)
rake server:debug  # Automatically includes internal docs

# Option 2: Explicit build
rake help:build_dev
```

#### 2. Searching Internal Documentation

When `DEBUG_MODE=true` is set, Monadic Help automatically includes internal documentation in search results:

```ruby
# In Monadic Help app
find_help_topics(text: "model spec vocabulary")
# Returns results from both docs/ and docs_dev/

# In Ruby code
help_db.find_closest_text("SSOT pattern", include_internal: true)
```

#### 3. Verifying Internal Docs are Loaded

```bash
# Connect to help database
docker exec -it monadic-chat-pgvector-container psql -U postgres -d monadic_help

# Check document counts
SELECT is_internal, COUNT(*) FROM help_docs GROUP BY is_internal;

# Expected output:
#  is_internal | count
# -------------+-------
#  f           |    45  -- External docs
#  t           |   154  -- Internal docs
```

### For Distribution

#### Building Packages

```bash
# Standard build (external docs only)
rake build

# Explicitly skip internal docs
SKIP_INTERNAL_DOCS=true rake build
```

The build process:
1. Processes only `docs/` directory (45 files)
2. Exports only `is_internal=false` entries
3. Packages contain no internal documentation
4. File size remains minimal

#### Verifying Export Contents

```bash
# Check exported files
cat docker/services/pgvector/help_data/metadata.json

# Verify no internal docs in export
docker exec -it monadic-chat-pgvector-container \
  psql -U postgres -d monadic_help \
  -c "SELECT COUNT(*) FROM help_docs WHERE is_internal = TRUE;"
# Should return 0 in exported database
```

## Implementation Details

### ProcessDocumentation

The documentation processor accepts an `include_internal` parameter:

```ruby
class ProcessDocumentation
  DOCS_PATH = ".../docs"
  DOCS_DEV_PATH = ".../docs_dev"  # Added

  def process_all_docs(include_internal: false)
    # Auto-detect DEBUG_MODE
    include_internal ||= (ENV['DEBUG_MODE'] == 'true')

    # Always process external docs
    process_language_docs("en", DOCS_PATH, is_internal: false)

    # Conditionally process internal docs
    if include_internal
      process_language_docs("en", DOCS_DEV_PATH, is_internal: true)
    end
  end
end
```

### Search Filtering

All search methods auto-detect `DEBUG_MODE`:

```ruby
module MonadicHelpTools
  def find_help_topics(text:, include_internal: nil)
    # Auto-detect if not explicitly specified
    include_internal = (ENV['DEBUG_MODE'] == 'true') if include_internal.nil?

    results = help_embeddings_db.find_closest_text_multi(
      text,
      include_internal: include_internal
    )
  end
end

class HelpEmbeddings
  def find_closest_text(text, include_internal: false)
    where_clause = include_internal ? "" : "WHERE hi.is_internal = FALSE"

    conn.exec_params(<<~SQL, [embedding, top_n])
      SELECT hi.*, hd.*
      FROM help_items hi
      JOIN help_docs hd ON hi.doc_id = hd.id
      #{where_clause}
      ORDER BY hi.embedding <=> $1::vector
      LIMIT $2
    SQL
  end
end
```

### Export Process

The export script explicitly filters internal documentation:

```ruby
class HelpDatabaseExporter
  def export_data
    # Export only external docs
    docs = conn.exec("SELECT * FROM help_docs WHERE is_internal = FALSE")

    # Export only items from external docs
    items = conn.exec(<<~SQL)
      SELECT hi.* FROM help_items hi
      JOIN help_docs hd ON hi.doc_id = hd.id
      WHERE hd.is_internal = FALSE
    SQL
  end
end
```

## Rake Tasks

### help:build
- **Purpose**: Build external documentation only
- **Usage**: `rake help:build`
- **Behavior**:
  - Processes `docs/` directory
  - Sets `is_internal=false` for all entries
  - Automatically exports after build
  - Used by `rake build` for package creation

### help:build_dev
- **Purpose**: Build external + internal documentation for development
- **Usage**: `rake help:build_dev`
- **Behavior**:
  - Processes both `docs/` and `docs_dev/`
  - Sets `is_internal=true` for `docs_dev/` entries
  - Does NOT export (internal docs stay local)
  - Called automatically by `rake server:debug`

### help:export
- **Purpose**: Export help database for distribution
- **Usage**: `rake help:export`
- **Behavior**:
  - Exports only `is_internal=false` entries
  - Creates schema.sql with `is_internal` column
  - Generates help_docs.json and help_items.json
  - Called automatically by `rake help:build`

## Performance Considerations

### Database Size

- **External only**: ~45 documents, ~500-1000 items
- **External + Internal**: ~199 documents, ~2000-4000 items (**4x increase**)

### Build Time

- **External only** (`rake build`): ~2-5 minutes
- **External + Internal** (`rake help:build_dev`): ~8-15 minutes (**3-4x slower**)

### Search Performance

Indexes on `is_internal` ensure filtering has minimal performance impact:

```sql
-- Fast query with index
SELECT * FROM help_docs WHERE is_internal = FALSE;
-- Uses idx_help_docs_is_internal
```

## Security Considerations

### What Gets Distributed

✅ **Included in packages:**
- `docs/` directory (external documentation)
- Exported database with `is_internal=false` only

❌ **Never included in packages:**
- `docs_dev/` directory
- Database entries with `is_internal=true`
- Developer notes, TODOs, implementation details

### Verification

Before release, verify:

```bash
# 1. Check export file size (should be ~1-5MB, not 10-20MB)
ls -lh docker/services/pgvector/help_data/*.json

# 2. Check export contents
jq '. | length' docker/services/pgvector/help_data/help_docs.json
# Should show ~45, not ~199

# 3. Verify no internal flag in export
jq '.[].is_internal' docker/services/pgvector/help_data/help_docs.json | sort -u
# Should only show 'false' or null, never 'true'
```

## Troubleshooting

### Internal docs not appearing in search

**Symptoms**: Monadic Help only returns external documentation

**Solutions**:
1. Check DEBUG_MODE is set: `echo $DEBUG_MODE` (should be `true`)
2. Verify internal docs are in database:
   ```sql
   SELECT COUNT(*) FROM help_docs WHERE is_internal = TRUE;
   ```
3. Rebuild help database: `rake help:build_dev`

### Internal docs appearing in production

**Symptoms**: Users report seeing developer documentation

**Solutions**:
1. Check export files: `grep is_internal docker/services/pgvector/help_data/*.json`
2. Rebuild export: `rake help:build` (not `help:build_dev`)
3. Verify no `DEBUG_MODE` in production environment

### Build time too long

**Symptoms**: `rake build` takes 15+ minutes

**Solutions**:
1. Check if `docs_dev/` is being processed (should not be)
2. Use `SKIP_HELP_DB=true rake build` to skip help DB entirely
3. Verify `include_internal: false` in build process

## Best Practices

### For Developers

1. **Use `rake server:debug` for development** - Automatically includes internal docs
2. **Keep internal docs organized** - Use clear file structure in `docs_dev/`
3. **Document internal features** - Add technical implementation notes to `docs_dev/developer/`

### For Maintainers

1. **Always use `rake build` for releases** - Never use `help:build_dev` for packages
2. **Verify export contents** - Check file sizes and `is_internal` flags before release
3. **Keep docs_dev/ out of .gitignore** - Internal docs should be version controlled
4. **Review internal docs regularly** - Remove outdated TODOs and temporary notes

### For Documentation

1. **External docs (`docs/`)**: End-user features, stable APIs, usage guides
2. **Internal docs (`docs_dev/`)**: Implementation details, architecture decisions, development workflows
3. **Temporary notes (`tmp/memo/`)**: WIP items, unresolved issues (not in help system)

## See Also

- [Help System Documentation](../../docs/advanced-topics/help-system.md) - Public documentation
- [ProcessDocumentation source](../../docker/services/ruby/scripts/utilities/process_documentation.rb)
- [HelpEmbeddings source](../../docker/services/ruby/lib/monadic/utils/help_embeddings.rb)
- [Export script source](../../docker/services/ruby/scripts/utilities/export_help_database_docker.rb)
