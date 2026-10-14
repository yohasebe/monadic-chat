# Test Quick Reference (Internal)

Which command to run when. Profiles are defined in `config/test/test-config.yml`; results go to `tmp/test_results/`. Details: [Test Runner](test_runner.md), [Testing Guide](testing.md).

## By Situation

| Situation | Command |
|---|---|
| Quick check | `rake test:profile[quick]` |
| During development | `rake test:profile[dev]` |
| Ruby, JavaScript and Python, no API | `rake test` |
| Before a commit | `rake test:profile[commit]` |
| Before a push (real API calls; keys in `~/monadic/config/env`) | `rake test:profile[ci]` |
| Everything, including media | `rake test:profile[full]` or `rake test:all[full]` |
| API changes for some providers | `rake matrix[openai,anthropic]` |
| Quick API check | `rake test:profile[smoke]` |

## Profiles

| Profile | Suites | API level |
|---|---|---|
| `quick` | unit | none |
| `dev` | unit, integration | none |
| `commit` | unit, integration | none |
| `ci` | unit, integration, api | standard |
| `full` | unit, integration, api, e2e | full |
| `smoke` | api | standard |

To add a profile, add an entry under `profiles:` in `config/test/test-config.yml`:

```yaml
profiles:
  my_custom:
    description: "My custom test configuration"
    suites: [unit, integration]
    api_level: none
    format: documentation
```

and run `rake test:profile[my_custom]`. `rake test:help` lists the suites and options. The runner (`lib/test_runner.rb`) reads `api_level`, `format` and `save` from a profile or a `test:run` option string; it ignores other keys.

## Results

| Command | Writes |
|---|---|
| RSpec (any runner) | `tmp/test_results/<run id>/`: `summary_compact.md`, `summary_full.md`, `rspec_report.json`, `env_meta.json` |
| `rake test` | `tmp/test_results/test_<timestamp>/`: `jest.json`, `pytest.txt`, `summary.json` |
| Unified runner (`test:run`, `test:profile`, `test:all`) | Per-suite JSON, `summary.json`, `index.html` in the run directory |

`tmp/test_results/latest` points to the last run.

| Task | Does |
|---|---|
| `rake test_summary:latest` | Prints the last RSpec summary |
| `rake test:history[5]` | Lists recent runs |
| `rake test:report` | Builds an HTML report of the latest run |
| `rake test:compare[run1,run2]` | Compares two runs |
| `rake test:analyze` | Extracts failures and pending from the last run |
| `rake test:cleanup[3]` | Deletes old runs, keeping the given number |

## More Options

```bash
rake test:run[unit,"format=documentation"]                      # verbose output
rake test:run[integration,"api_level=none,save=true"]           # override settings
cd docker/services/ruby && bundle exec rspec spec/unit/specific_spec.rb   # one file
EXTRA_LOGGING=true rake test:profile[dev]
```

## Troubleshooting

| Problem | Check |
|---|---|
| Tests not found | Run rake from the project root |
| API keys not loaded | `~/monadic/config/env` exists and has the provider's key (check without printing values) |
| Docker errors | Start Docker Desktop, or use `rake test:profile[quick]` (no Docker) |
| Profile not found | `rake test:help`, and the names in `config/test/test-config.yml` |
