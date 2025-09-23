# Error Handling Architecture

This note summarizes the runtime safeguards that keep long-running agent sessions recoverable. Use it as a map when debugging retries or unexpected stops.

## ErrorPatternDetector
- File: `docker/services/ruby/lib/monadic/utils/error_pattern_detector.rb`
- Tracks recent tool errors per session and categorizes common failures (fonts, missing modules, permissions, resources, plotting, file I/O, network).
- After three similar errors the detector signals that retries should stop and returns a user-facing suggestion block summarizing next steps.
- History is capped at the last 10 entries; specs can inject synthetic errors to validate the stop condition.

## FunctionCallErrorHandler
- Mixin consumed by vendor helpers (OpenAI, Claude, Gemini) to connect tool responses to the detector.
- `handle_function_error` records the failure, emits a fragment with mitigation guidance, and sets `session[:parameters]["stop_retrying"]` when the detector asks to stop.
- `reset_error_tracking(session)` clears state for new conversations; call it when manually rewinding a session during debugging.

## NetworkErrorHandler
- Wraps outbound HTTP calls with exponential backoff (`with_network_retry`).
- Provider-specific timeout overrides (`PROVIDER_TIMEOUTS`) guard slow APIs such as Claude or DeepSeek.
- `format_network_error` maps low-level exceptions to user-friendly messages. When retries are exhausted a `RuntimeError` surfaces with the formatted text, so UI copy stays centralized here.

## Practical checklist
- When investigating “stuck” tools, dump `session[:error_patterns]` to see what pattern was matched and whether `stop_retrying` is set.
- Avoid bypassing `with_network_retry` in new adapters: it keeps latency spikes from cascading into repeated tool failures.
- For new error classes, extend `SYSTEM_ERROR_PATTERNS` and update the suggestion strings; keep the tone action-oriented and concise.

## Related tests
- `spec/unit/utils/error_pattern_detector_spec.rb`
- `spec/unit/utils/function_call_error_handler_spec.rb`
- `spec/unit/utils/network_error_handler_spec.rb`

These specs double as executable documentation—skim them before changing retry thresholds or categories.
