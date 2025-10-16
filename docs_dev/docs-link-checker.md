# Documentation Link Checker

## Overview

The documentation link checker is a lint tool that validates all internal links in the `docs/` and `docs_dev/` directories to ensure they point to existing files.

## Purpose

- Prevents broken links in documentation
- Automatically detects missing files or incorrect paths
- Helps maintain documentation quality as the codebase evolves

## Usage

### Run the checker

```bash
# Using npm script (recommended)
npm run lint:docs-links

# Or run directly
ruby scripts/lint/check_docs_links.rb
```

### Exit codes

- `0`: All links are valid
- `1`: Broken links found

## What it checks

The checker validates:

✅ **Internal markdown links** - `[text](path/to/sample-file.md)`
✅ **Relative paths** - `../other-dir/sample-file.md`
✅ **Absolute paths** - `/path/from/docs/sample-root.md`
✅ **Directory links** - `frontend/` (expects `frontend/README.md`)
✅ **Links without .md extension** - Automatically tries `.md` extension
✅ **Anchor links with files** - `sample-file.md#section` (validates file exists)

## What it ignores

The checker skips:

🔸 **External links** - `http://`, `https://`, `ftp://`
🔸 **Email addresses** - `name@example.com`
🔸 **Anchor-only links** - `#section-name`
🔸 **Sample links** - Links containing `sample` keyword (e.g., `sample-file.md`)
🔸 **Docsify size notation** - Strips `:size=40` before validation
🔸 **Code blocks** - Links inside ` ``` ` fenced code blocks

## How it works

1. **Scans all markdown files** in `docs/` and `docs_dev/`
2. **Extracts links** using regex pattern `\[text\](url)`
3. **Resolves paths** considering:
   - Current file location (for relative paths)
   - Documentation root (for absolute paths)
   - Japanese version paths (`/ja/`)
4. **Checks file existence** and reports violations

## Path resolution examples

### Absolute paths
```markdown
<!-- In docs/README.md -->
[Link](/advanced-topics/sample-foo.md)
→ Resolves to: docs/advanced-topics/sample-foo.md

<!-- In docs_dev/ja/README.md -->
[Link](/ja/frontend/)
→ Resolves to: docs_dev/ja/frontend/README.md
```

### Relative paths
```markdown
<!-- In docs/advanced-topics/sample-foo.md -->
[Link](../getting-started/sample-bar.md)
→ Resolves to: docs/getting-started/sample-bar.md

<!-- In docs_dev/ruby_service/README.md -->
[Link](testing/sample-overview.md)
→ Resolves to: docs_dev/ruby_service/testing/sample-overview.md
```

### Directory links
```markdown
[Frontend](frontend/)
→ Checks for: frontend/README.md
```

## Common issues and fixes

### Issue: Link to non-existent file

**Error:**
```
docs/README.md:15
  Link: [Foo](advanced-topics/foo.md)
  Resolved to: docs/advanced-topics/foo.md
  Error: Link target does not exist
```

**Fix:**
- Create the missing file, or
- Remove/update the link

### Issue: Wrong path format

**Error:**
```
docs_dev/ja/README.md:20
  Link: [Test](../test.md)
  Resolved to: docs_dev/test.md
  Error: Link target does not exist
```

**Fix:**
- Use absolute path: `[Test](/ja/sample-test.md)`
- Or create the missing translation

### Issue: Directory without README

**Error:**
```
docs_dev/frontend/README.md:10
  Link: [Components](sample-components/)
  Resolved to: docs_dev/frontend/sample-components/README.md
  Error: Link target does not exist
```

**Fix:**
- Create `sample-components/README.md`, or
- Link to specific file instead

## Integration with CI/CD

While Monadic Chat doesn't currently use CI, this checker can be integrated into:

- **Pre-commit hooks** - Validate links before commits
- **GitHub Actions** - Run on pull requests
- **Local development** - Part of documentation workflow

## Technical details

- **Script location**: `scripts/lint/check_docs_links.rb`
- **Language**: Ruby (uses Pathname for path handling)
- **Dependencies**: None (uses Ruby standard library)
- **Performance**: Fast (~1 second for ~100 files)

## Maintaining the checker

### Adding new link patterns

Edit `LINK_PATTERN` in `check_docs_links.rb`:
```ruby
LINK_PATTERN = /\[([^\]]+)\]\(([^)]+)\)/
```

### Ignoring specific patterns

Add to `external_link?()` method:
```ruby
def external_link?(url)
  url.start_with?('http://', 'https://') ||
    url.match?(/your-pattern-here/)
end
```

### Changing target directories

Modify `DOCS_DIRS` array:
```ruby
DOCS_DIRS = [ROOT.join('docs'), ROOT.join('docs_dev')]
```

## See also

- [Debug Mode & Local Docs](server-debug-mode.md) - How to view documentation locally
- [Common Issues](common-issues.md) - Troubleshooting guide
