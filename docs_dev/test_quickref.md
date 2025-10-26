# Test Quick Reference (Internal)

For Monadic Chat maintainers. This guide shows the **recommended** way to run tests.

## Philosophy

- **Simple**: Use `rake test` for basic testing (Ruby + JavaScript + Python)
- **Profile-based**: Use `rake test:profile[name]` for specific scenarios
- **Declarative**: Test configurations live in `config/test/test-config.yml`
- **Unified Results**: All test results saved to `./tmp/test_results/`

## Daily Workflow

### During Development

```bash
# Quick check (unit tests only, ~10-30s)
rake test:profile[quick]

# Standard development testing (unit + integration, ~1-2min)
rake test:profile[dev]

# Simple all-tests run (Ruby + JS + Python, no API, ~2-3min)
rake test
```

### Before Commit

```bash
# Pre-commit verification (same as dev with detailed output)
rake test:profile[commit]
```

### Before Push / PR

```bash
# CI-equivalent tests (includes real API calls, ~3-5min)
# Requires API keys in ~/monadic/config/env
rake test:profile[ci]
```

### Full Test Suite

```bash
# Complete test suite including media tests (~10-15min)
# Requires all API keys configured
rake test:profile[full]

# Alternative: Direct unified runner with media tests
rake test:all[full]
```

## Available Profiles

| Profile   | Suites              | API Calls | Media | Speed    | Use Case                    |
|-----------|---------------------|-----------|-------|----------|-----------------------------|
| `quick`   | unit                | No        | No    | ⚡ Fast  | Quick sanity check          |
| `dev`     | unit + integration  | No        | No    | 🏃 Medium| Daily development           |
| `commit`  | unit + integration  | No        | No    | 🏃 Medium| Pre-commit verification     |
| `ci`      | unit + int + api    | Yes       | No    | 🐢 Slow  | CI pipeline / pre-push      |
| `full`    | all suites          | Yes       | Yes   | 🐌 Very Slow | Complete verification |
| `smoke`   | api only            | Yes       | No    | 🏃 Medium| Quick API sanity check      |

## Common Scenarios

### I broke something and need a quick check
```bash
rake test:profile[quick]
```

### Working on integration features
```bash
rake test:profile[dev]
```

### Ready to commit
```bash
rake test:profile[commit]
```

### Testing API integration changes
```bash
# Specific providers only
rake test:run[api,"providers=openai,anthropic,api_level=standard"]

# Or use smoke profile for quick verification
rake test:profile[smoke]
```

### Debugging test failures
```bash
# Run with verbose output
rake test:run[unit,"format=documentation"]

# View last test results
rake test:history[5]

# View detailed HTML report
rake test:report
```

## Understanding Output

### Artifacts Location
All test results are centralized in `./tmp/test_results/`:

```
tmp/test_results/
├── latest/                           # Symlink to most recent Ruby test run
├── <run_id>/                         # Ruby test results directory
│   ├── summary_compact.md            # Concise summary
│   ├── summary_full.md               # Detailed results
│   └── rspec_report.json             # Machine-readable JSON
├── <run_id>_jest.json                # JavaScript test results (Jest)
├── <run_id>_pytest.txt               # Python test output
├── all_<timestamp>.json              # Unified test suite summary
└── index_all_<timestamp>.html        # Combined results dashboard
```

### Quick Summary
```bash
# View last test results
rake test:summary:latest

# Compare two runs
rake test:compare[run1,run2]
```

## Configuration

### API Keys
Configure in `~/monadic/config/env`:
```bash
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
```

### Custom Profiles
Edit `config/test/test-config.yml` to add custom profiles:
```yaml
profiles:
  my_custom:
    description: "My custom test configuration"
    suites: [unit, integration]
    api_level: none
    format: documentation
    timeout: 60
```

Then run:
```bash
rake test:profile[my_custom]
```

## Deprecated Tasks (Do Not Use)

❌ **Old style** (complex, error-prone):
```bash
# DON'T USE THESE ANYMORE
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke
ENV['API_TIMEOUT']=120 rake spec_e2e:chat
```

✅ **New style** (simple, declarative):
```bash
# USE THESE INSTEAD
rake test:profile[smoke]
rake test:run[e2e,"suite=chat,timeout=120"]
```

### Migration Guide

| Old Command | New Command |
|-------------|-------------|
| `rake spec_unit` | `rake test:profile[quick]` |
| `rake spec_integration` | `rake test:profile[dev]` |
| `RUN_API=true rake spec_api:smoke` | `rake test:profile[smoke]` |
| `rake spec_e2e` | `rake test:profile[full]` |

## Tips

1. **Start small**: Use `quick` or `dev` during active development
2. **Run commit profile before committing**: Catches integration issues early
3. **Save CI for push**: API tests are slow and consume quota
4. **Use HTML reports**: Much easier to review than terminal output
5. **Check history**: Compare before/after when fixing bugs

## Troubleshooting

### Tests not found
```bash
# Ensure you're in the project root
cd /path/to/monadic-chat
rake test:profile[dev]
```

### API keys not loaded
```bash
# Check config file exists
ls -la ~/monadic/config/env

# Verify keys are set
grep API_KEY ~/monadic/config/env
```

### Docker errors
```bash
# Start Docker Desktop manually
# Or skip Docker tests
rake test:profile[quick]  # No Docker needed
```

### Profile not found
```bash
# List available profiles
rake test:help

# Check profile name in config
cat config/test/test-config.yml
```

## Advanced Usage

### Override profile settings
```bash
# Use dev profile but with different timeout
rake test:run[integration,"timeout=120,api_level=none"]
```

### Run specific test files
```bash
# RSpec directly
bundle exec rspec spec/unit/specific_spec.rb

# Or use the runner
rake test:run[unit,"files=spec/unit/specific_spec.rb"]
```

### Custom test environments
```bash
# Set environment variables before running
EXTRA_LOGGING=true rake test:profile[dev]
```

## Next Steps

- Full details: `docs_dev/test_runner.md`
- Profile config: `config/test/test-config.yml`
- Implementation: Search for `task 'test:profile'` in `Rakefile`
