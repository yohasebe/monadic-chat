# Architecture Hardening Plan

Status: **active**, kicked off 2026-05-03 after the comprehensive beta.16 audit.

This is internal documentation for the Monadic Chat maintainer. The goal is
to reduce the rate of "found by manual dogfood, days before release"
defects by codifying detection of the failure modes we have already
encountered, centralising the operations that produce them, and replacing
mock-heavy unit tests with route-level integration tests where they
actually catch things.

The plan is **deliberately deprecate-then-migrate**: every new helper or
rule lands as an additive change first, baselines existing violations,
and is only tightened to a hard error after all callers have been
migrated. The codebase keeps working at every step.

---

## 1. Why now

The beta.16 release audit (rebuild #1 → rebuild #4 over a single day)
turned up six distinct bugs. Each one was symptomatic of a different
gap, and each one had been quietly broken for weeks or longer:

| # | Defect | Surface |
|---|---|---|
| A | `fetch('/document')` lacked `X-Requested-With`, so Sinatra's `request.xhr?` branch fell through to a non-JSON response. | `Text from file` button errored with `No number after minus sign in JSON at position 2`. |
| B | Same as A for `/fetch_webpage` and `/load`, in both `form-handlers.js` and the fallback `shims.js`. | `Text from URL` button errored identically. |
| C | `jupyter_helper.rb` hard-coded `/Users/yohasebe/monadic/data` as the dev-mode shared volume. | Jupyter kernel restart broke for any developer whose home directory is not `/Users/yohasebe`. |
| D | `app.rb#fetch_webpage` interpolated the user-supplied URL into a `bash -c` string without `Shellwords.escape`. | Shell command injection via `Text from URL` (defence at client only, server-side trust). |
| E | `cards.js` inline-edit replaced only the first `<p>` with a textarea; multi-block markdown left stale `<ul>`/`<p>` rendered below the textarea. | Visible UI defect when editing assistant replies with lists. |
| F | `library-panel.js`'s Save button was clickable for empty sessions and `openSaveModal` had no precondition guard, so a user could open the Save modal with zero messages. | Empty Library entries possible from the UI. |

None of these were caused by the Track 1–5 work that beta.16 actually
ships. They are pre-existing latent defects that the audit happened to
expose because the audit started reading every file in the extraction
path. **That is exactly the symptom we want to address: latent issues
should fail loudly in CI, not surface during a release audit.**

## 2. Root-cause taxonomy

Mapping the six defects onto failure classes, three patterns dominate:

### 2.1. Implicit cross-layer contracts (A, B)

`request.xhr?` is a server-side *expectation* of a client header. There
is no compiler, linter, or test that pairs the two. When the codebase
migrated from jQuery (which sets `X-Requested-With` automatically) to
`fetch()` (which does not), three Sinatra routes silently fell off the
JSON-return path. The defect was invisible until a user clicked the
button — even unit tests would not trip it because they exercised the
route handler directly without going through the fetch layer.

### 2.2. Escapes from a working abstraction (C, D)

`Monadic::Utils::Environment.data_path` already resolves to the right
shared-volume path in either container or dev mode. `jupyter_helper.rb`
re-implemented the same logic and hard-coded the maintainer's own home
directory. Similarly, `Shellwords.escape` is used correctly in the PDF
and Office paths but not in the URL path. **The abstractions exist; the
problem is that there is no incentive (lint, test, code review
checklist) to use them, and the codebase has enough surface area that a
new file can quietly opt out.**

### 2.3. Implicit DOM / state assumptions (E, F)

`cards.js` assumed Markdown rendering produces a single `<p>` element.
`library-panel.js` assumed nobody could click "Save" without messages.
Both are *single-layer defences* — the moment the assumption is wrong,
the defect surfaces directly to the user. Defence-in-depth (multiple
guard layers, fixtures with realistic structure) prevents this.

## 3. Three-axis improvement strategy

### 3.1. Axis 1: anti-pattern lint (catch the regression in CI)

Each of the six defects above is detectable by static inspection. The
plan is to add a `rake lint:anti_patterns` task that runs in CI and
fails the build when any of the patterns reappear. To stay safe, every
rule lands as **warn-only with a documented baseline** of existing
violations; once each baseline reaches zero we promote the rule to
error. This means rolling out a rule never breaks the tree, even on the
first commit.

Rules to land in this phase, with concrete grep / AST patterns:

| Rule ID | Detects | Baseline (post-audit) |
|---|---|---|
| `lint/personal_paths` | string literals matching `/Users/<name>/`, `/home/<name>/`, or `C:\Users\<name>\` inside `app/`, `docker/services/**`. Tests excluded. | 0. Locked in. |
| `lint/shell_escape` | shell-string indicators (`docker exec`, `bash -c`, `system("...")`) with `#{...}` interpolation where the interpolated identifier is not in the safe list (`SHARED_VOL`, `escaped_*`, `safe_*`, server-generated names). | 0. Found `video_analyze_agent.rb` filename injection during audit; fixed and locked in. |
| `lint/xhr_pair` | every `request.xhr?` in `lib/monadic/routes/**` must be paired with `X-Requested-With` in every `fetch()` call to that path in `public/js/**`. Bidirectional. | 0. 6 callers verified. |
| `lint/data_path_literals` | `"/monadic/data"` outside the Environment helper or its constant definition. | 17 in baseline (allowlisted; mostly dual-mode fallback in scripts and Sinatra HTTP route). New violations fail the build; existing ones are tracked for migration to `Environment.data_path`. |
| `lint/multiblock_edit` (frontend) | jest fixture for `cards.js` inline edit of multi-block markdown. | Tracked separately under H4; not part of the rake task. |

Each rule script accepts `--baseline N` so it can be relaxed on a
per-rule basis if a refactor needs to land first. The CI workflow runs
the strict (no `--baseline`) form so any new violation fails the PR.

### 3.2. Axis 2: centralised safe operations (remove the temptation)

Three thin helpers, each replacing a class of defect:

#### `Monadic::Shell` (server-side)

```ruby
# Args are taken as an array so callers cannot accidentally
# string-interpolate. Every interpolated value goes through the
# argv channel of Open3.capture3, which has no shell at all.
Monadic::Shell.docker_exec(
  container: :python,             # symbol → resolves the full container name
  workdir:   :shared_volume,      # symbol → resolves to /monadic/data via Environment
  command:   ["pdf2txt.py", filename, "--format", "md"]
)
```

Rationale: most of the existing `docker exec` callsites use heredoc
strings and *do* escape correctly, but the safer path is "take args as
an array, never see a shell." The helper also centralises the
"container name → full Docker name" map and the `/monadic/data` vs
`~/monadic/data` resolution that several files currently do by hand.

#### `monadicFetch` (frontend)

```js
// Always sets X-Requested-With, parses JSON, normalises errors.
// Throws a structured error object instead of returning whatever
// happened to come back when the server returned non-JSON.
const data = await monadicFetch.postJson('/document', formData);
```

Rationale: the X-Requested-With contract was the *first* failure class
to land in this audit. A wrapper makes it impossible to forget.

#### `Monadic::JsonRoute` (server-side, Sinatra extension)

```ruby
post '/document', json: true do
  # content_type is set automatically. The block can return a Hash;
  # to_json is called for you. There is no fallback non-JSON branch
  # that a missing X-Requested-With could divert to.
end
```

Rationale: removes the `request.xhr?` branching pattern entirely from
new code. The three existing routes that use it stay as-is until
migrated.

Each helper lands behind a feature toggle: a single POC migration in a
non-critical callsite to validate the API, *then* the rest as a
gradual sweep.

### 3.3. Axis 3: route-level integration tests (catch what mocks miss)

Every defect found in this audit was either invisible at the unit-test
level or actively papered over by mocks. The Library save flow had
unit tests for `submitSave`'s precondition check, but the Save button
itself was never exercised against an empty `window.messages`. The
PDF extraction path had unit tests for the JSON shape but no test that
posted via fetch and parsed the response, which is exactly where the
X-Requested-With bug lived.

Concrete integration tests to add (each runs against real Docker
containers, behind an opt-in env flag so unit-test runs stay fast):

| Test | Flow it exercises | Defect class it would have caught |
|---|---|---|
| `text_from_file_smoke` | UI form post → `/document` → `pdf2txt.py` → fetch.json() | A (X-Requested-With), D-class (escape), JSON shape |
| `text_from_url_smoke` | UI form post → `/fetch_webpage` → `webpage_fetcher.py` | B, D (URL injection), encoding |
| `library_import_smoke` | upload → file_importer → extractor or pdfplumber → store | extractor fallback, Chonkie chunks, conv_id sticky |
| `library_save_empty_session` | Save click with empty messages | F (Save guard) |
| `inline_edit_multiblock` | render multi-block markdown → enter edit → assert no leftover | E (cards.js) |
| `dev_mode_path_parity` | run each smoke under both `IN_CONTAINER=true` and `false` | C (personal path leaks) |

The `dev_mode_path_parity` matrix is the single highest-value addition
because *every* path-resolution defect in this codebase has the same
shape: works in production, breaks in dev mode. Running the smoke suite
under both modes catches them all.

## 4. Phased roadmap

| Phase | Scope | Risk | Deliverable | Status |
|---|---|---|---|---|
| H1 | This document. | none | `docs_dev/architecture_hardening_plan.md` | ✅ landed |
| H2 | Anti-pattern lint (Axis 1). Four rules + CI hookup. Each rule fails the build when a new violation is introduced. Existing violations are baselined via per-file allowlists so the rules can land without rewriting history. | low | `rake lint:anti_patterns` (Rakefile), `scripts/lint/check_*.rb` (4 scripts), `.github/workflows/lint.yml` | ✅ landed |
| H3 | Centralised helpers (Axis 2). Three helpers added, one POC migration each. Existing callers untouched. | medium | `Monadic::Shell`, `monadicFetch`, `Monadic::JsonRoute` + POC migrations | 4–6 |
| H4 | Integration test infrastructure (Axis 3). Opt-in real-Docker smokes for the six flows above. | medium | `spec/integration/smoke/**`, dev-mode parity matrix | 8–12 |
| H5 | Sweep migration. Every existing `docker exec`, `fetch()` to xhr-route, `request.xhr?` route migrated to its helper. One callsite per commit. | low (but high in volume) | n × small commits | 20–40 |
| H6 | Tighten the lint. Promote each rule from warn to error once its baseline reaches zero. CI starts blocking PRs that re-introduce these patterns. | low | rule-by-rule promotion | 3–5 |

H1–H4 are pure additions: none of the existing user-visible behaviour
changes. H5 is the only phase that rewrites runtime code, and even
there the helpers have been validated by H3's POCs first. H6 is just a
config switch; by the time we reach it the codebase already complies.

## 5. Open questions / non-goals

### Questions to resolve before each phase
- **H2** rule wording: do we use rubocop custom cops or a standalone
  ruby script? rubocop integrates with editors but custom cops are
  surprisingly verbose. A flat `scripts/lint/check_anti_patterns.rb`
  with one method per rule is probably enough for now.
- **H3** Sinatra `JsonRoute` vs always-on `content_type :json`: do we
  add a mixin or just remove the `request.xhr?` branching from the
  three existing routes? The latter is a smaller change but loses the
  reusable affordance.
- **H4** Integration test runtime budget: real-Docker tests can take
  minutes. Need to decide which CI lane runs them (every PR? nightly?
  release-only?) and whether to gate behind a label.

### Explicit non-goals
- No retrofit of existing test suites onto unrelated providers. The
  audit covers Track 1–5 territory; the rest of the codebase is fine.
- No reformatting / cosmetic refactors. Every commit in this plan must
  be defensible as "fixes a real defect class."
- No new abstractions beyond the three helpers above. Adding more
  abstraction surface is itself a failure class.

## 6. Success criteria

We will know the plan worked when:

1. The next user-found defect of the form "fetch returns garbage" or
   "shell command misbehaves on weird input" or "works on my machine
   but not on yours" has its root-cause class already covered by an
   anti-pattern rule, a helper, or a smoke test.
2. The lint task can be promoted to error on every rule (= zero
   violations across the codebase) within the timeline above.
3. The release-day audit needs less than 30 minutes because the smoke
   suite has run automatically.

## 7. Working notes

- This file is a living plan. As phases land, update the table above
  with the actual commit hash that closed each row, and append any
  new patterns we discover.
- The plan is intentionally **scoped to the patterns the beta.16 audit
  surfaced**. It is not a general code-quality manifesto; broader
  refactors should be considered separately.
- Cross-referenced from `MEMORY.md` so future sessions pick up where
  this one left off.
