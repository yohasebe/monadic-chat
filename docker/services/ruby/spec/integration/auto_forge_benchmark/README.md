# AutoForge Benchmark Suite

End-to-end benchmark for AutoForge Claude variants. Used to evaluate
the optimal orchestrator + code-subagent combination on representative
tasks. Results inform `providerDefaults.anthropic.code` and inform
future model migrations.

This suite is **tracked** in git (re-runnable across releases) but is
NOT part of the standard `rake spec:quick` flow because each run makes
real LLM API calls and takes minutes to hours. Invoke it explicitly
with the runner described below.

## Status

- **Step 2a (this commit)**: Scaffold only. Tasks defined, runner skeleton,
  scorers stubbed. No real LLM calls yet.
- **Step 2b (next)**: Wire up the 3 configs (A/B/C) and execute benchmark
  runs against the Anthropic API. Real LLM calls. Cost ~$5-20 per full
  matrix depending on task complexity.
- **Step 2c**: Analyze results, document in
  `research_notes/autoforge_benchmark_results.md`, decide on
  providerDefaults update.

See `research_notes/4_step_plan.md` Step 2 for the broader context and
`research_notes/autoforge_benchmark_design.md` for the design rationale.

## Structure

```
auto_forge_benchmark/
├── README.md              # This file
├── tasks/                 # Task specifications (one per task)
│   ├── easy_calculator.yml
│   ├── medium_markdown_editor.yml
│   └── hard_chat_ui.yml
├── runners/               # Execution scripts
│   └── runner.rb          # Main entry point (Step 2b)
├── scorers/               # Evaluation logic
│   ├── functional_scorer.rb     # Selenium smoke test
│   ├── rubric_scorer.rb         # Spec coverage rubric
│   └── quality_scorer.rb        # Code quality (lint + readability)
└── results/               # Generated, gitignored
    └── <timestamp>/       # Per-run results directory
        ├── <task>-<config>/<artifacts>
        └── summary.json
```

## Tasks

Each task is defined by a YAML spec under `tasks/`. See
`tasks/easy_calculator.yml` for the format. Tasks declare:

- A natural-language `description` (the AutoForge user input)
- `rubric_items`: spec coverage criteria (binary or graded)
- `smoke_test`: Selenium operations that verify basic functionality
- `loc_target`: expected lines of code (rough)
- `difficulty`: easy / medium / hard

## Configs

Each config combines an orchestrator model + a code-subagent model:

- **A** (baseline): `claude-sonnet-4-6` → `claude-sonnet-4-6`
- **B** (anti-inverted): `claude-sonnet-4-6` → `claude-opus-4-7`
- **C** (cost-optimized): `claude-haiku-4-5-20251001` → `claude-sonnet-4-6`

Defined in `runners/runner.rb` as `CONFIGS`. Add or remove by editing
that constant.

## Metrics collected per (task × config) run

| Metric | Source |
|--------|--------|
| `functional_pass` | Selenium smoke test passed (bool) |
| `rubric_coverage` | Fraction of `rubric_items` satisfied (0.0–1.0) |
| `code_quality_score` | Lint + readability rubric (0–10) |
| `iteration_count` | Number of LLM calls made |
| `total_latency_sec` | Wall clock from start to completion |
| `input_tokens` / `output_tokens` | Anthropic API usage |
| `estimated_cost_usd` | Token counts × per-model pricing |

Results are written to
`results/<timestamp>/<task>-<config>/result.json` and aggregated in
`summary.json`.

## How to invoke (Step 2b onwards)

```bash
# From docker/services/ruby/
cd docker/services/ruby

# Run all tasks × all configs (one full matrix)
bundle exec ruby spec/integration/auto_forge_benchmark/runners/runner.rb

# Run a single task × single config
bundle exec ruby spec/integration/auto_forge_benchmark/runners/runner.rb \
  --task easy_calculator --config A

# Dry run (no LLM calls, validates spec)
bundle exec ruby spec/integration/auto_forge_benchmark/runners/runner.rb \
  --dry-run
```

Requires `ANTHROPIC_API_KEY` in `~/monadic/config/env`. Each full matrix
takes ~30 minutes to several hours depending on task complexity and
selected configs.

## CI integration (future)

This suite is NOT in the default CI pipeline (too slow + costly). When
the matrix stabilizes, consider a scheduled nightly or weekly job that
runs against a fixed model snapshot. See Step 2c judgment.

## What this suite does NOT do

- Compare against OpenAI, Grok, or other providers (out of scope, future)
- Test Managed Agents (out of scope; see `research_notes/4_step_plan.md`
  Step 4 for that activity)
- Replace `spec/integration/apps/auto_forge_*` smoke tests (those verify
  the implementation; this measures quality)
- Run on every PR (too slow + cost)
