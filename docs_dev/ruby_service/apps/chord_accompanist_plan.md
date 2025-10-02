# Chord Accompanist Multi-Agent Plan

## Goal
Eliminate infinite validation loops by restructuring the accompaniment generation workflow into discrete stages handled by specialized agents.

## Proposed Agents
1. **RequirementsAgent**
   - Gather tempo, time signature, key, instrument style, desired length.
   - Output a `requirements.json` object with validated defaults.

2. **ProgressionAgent**
   - Take requirements and optional reference song.
   - Produce a structured chord progression (per bar) in JSON (e.g., `{ sections: [{ name: "Verse", bars: ["C", "G" ...] }] }`).
   - Responsible for explaining assumptions (e.g., choosing 8 bars for verse).

3. **ArrangementAgent**
   - Combine progression and style templates to produce ABC skeleton.
   - Applies deterministic templates (arpeggio, block chords, walking bass) stored locally.
   - Ensures ABC structural correctness (headers, bar separators, single voice).

4. **ValidationAgent**
   - Run ABCJS validation and preview.
   - On failure: attempt automatic fixes (bar length adjustments, removing trailing content).
   - If still failing after N attempts, returns a failure summary instead of looping.

5. **SummaryAgent** (optional)
   - Compose the final user message (requirements recap, preview link, ABC code).

## Data Flow
```
User input -> RequirementsAgent -> requirements.json
requirements.json -> ProgressionAgent -> progression.json
requirements + progression -> ArrangementAgent -> draft.abc
ValidationAgent(draft.abc) -> { success, final_abc, preview }
Success -> SummaryAgent -> user response
Failure -> SummaryAgent -> explain failure
```

## Steps to Implement
1. Draft JSON schemas for `requirements.json` and `progression.json`.
2. Update MDSL to orchestrate multi-agent calls.
3. Build Ruby helpers for templates & validation.
4. Create integration tests simulating typical conversations.

## Implementation Notes (2025-10-02)
- Added `run_multi_agent_pipeline` tool entry in the MDSL with explicit payload requirements so the main assistant only calls it after gathering inputs.
- Introduced `ChordAccompanist::Pipeline`, which encapsulates Requirement/Progression generation (via structured JSON), deterministic arrangement templates, and consolidated metadata propagation.
- Deterministic arrangement currently supports block, pulse, and arpeggio patterns with ASCII-only chord parsing and fallback handling for unknown symbols.
- Validation remains in the Ruby tool layer: sanitized ABC is fed to ABCJS; validation failures break the loop by returning `success: false` with the original error message.
- Added a unit spec (`spec/unit/chord_accompanist_pipeline_spec.rb`) that exercises the pipeline using fully-specified inputs to avoid network calls and API dependencies.
- The pipeline now parses structured `notes` payloads (e.g. `requirements: {...}; progression_hint: [...]`) so the assistant can pass precomputed data without re-contacting upstream agents; JSON extraction falls back to defaults if parsing fails.
