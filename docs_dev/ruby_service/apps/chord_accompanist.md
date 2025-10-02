# Chord Accompanist Prototype Notes

- ABC notation is normalised on both Ruby and JS sides (HTML decode, unicode dashes/quotes → ASCII, repeated blank lines collapsed, brackets cleaned).
- Validation uses ABCJS inside Selenium, mirroring the Mermaid Grapher approach.
- `preview_abc` renders the score and captures a PNG. MIDI support is not yet wired, but filenames are reserved for future use.
- Workflow mirrors Mermaid Grapher: `validate_abc_syntax` → `preview_abc` → respond.
- `run_multi_agent_pipeline` can accept the assistant's structured payload (`context` + `notes`). When `notes` includes JSON-like segments (`requirements: {...}; progression_hint: [...]`), the Ruby side extracts them and skips additional LLM calls, reducing tool retry loops.

Considerations for future work:
- Expose downloadable SVG/MIDI when ABCJS APIs are integrated.
- Add automatic chord-progression templates or reference-based inference.
- Include regression tests for sanitiser (unicode dash, smart quotes, extra blank lines).
