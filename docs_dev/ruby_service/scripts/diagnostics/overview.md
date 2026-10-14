# Diagnostics

The scripts in `docker/services/ruby/scripts/diagnostics/` are run by hand with `bundle exec ruby <script>` from `docker/services/ruby/`. They are not part of the test suites and need no API key or container.

| Script | What it does |
|---|---|
| `benchmark_monadic.rb` | Times `Monadic::JsonHandler` operations on sample data |
| `test_stt_error.rb` | Prints the error messages `InteractionUtils` produces for simulated STT failures |

`test_monadic_simple.rb`, `test_web_insight.rb` and `apps/wikipedia/test_wikipedia_loading*.rb` fail to load with the current code (missing files and an unloaded helper module).
