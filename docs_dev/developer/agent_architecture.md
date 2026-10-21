# Agent Architecture

Agents are Ruby modules in `lib/monadic/agents/` that carry out a task the chat model delegates or that runs beside the chat: media analysis, code generation, context extraction, second opinions and the AI User. `app.rb` requires every file in the directory; `MonadicApp` includes `ImageAnalysisAgent` and `AudioTranscriptionAgent`.

| Category | Agents | Provider |
|---|---|---|
| Media analysis | `ImageAnalysisAgent`, `AudioTranscriptionAgent` (with the timed transcription in `timed_audio_transcription.rb`), `VideoAnalyzeAgent`, `AudioAnalysisAgent` | The app's own provider, or an error |
| Code generation | `Monadic::Agents::OpenAICodeAgent`, `ClaudeCodeAgent`, `GrokCodeAgent` | The provider of the app variant that includes it |
| Conversation | `SecondOpinionAgent`, `ContextExtractorAgent`, `AIUserAgent` | Chosen per call (see below) |

## Media Analysis

### Provider Rule

`Monadic::Utils::ProviderCapabilities.resolve(capability, app_provider)` returns `{provider:}` or `{error: "ERROR: …"}`. An analysis runs on the app's own provider; it is never sent to another provider because that provider has a key.

| Capability | Providers |
|---|---|
| `:image` | openai, anthropic, google, xai, mistral, cohere, deepseek |
| `:video` | openai, anthropic, google, xai |
| `:audio` | openai, google, xai |

The error says that the capability is not available for the provider, or which API key is missing. Models come from `providerDefaults` through `ModelSpec.default_vision_model` / `default_audio_model`.

### Agents

| Agent | Method | Notes |
|---|---|---|
| `ImageAnalysisAgent` | `image_analysis_agent(message:, image_path:, detail:)` | The path must be an image inside the shared folder (`SharedPathGuard`); 10 MB limit |
| `AudioTranscriptionAgent` | `audio_transcription_agent(audio_path:, model:, response_format:, lang_code:)` | OpenAI `/v1/audio/transcriptions`, Gemini `generateContent` with inline audio, xAI `/v1/stt`; 25 MB limit |
| `AudioTranscriptionAgent` (`timed_audio_transcription.rb`) | `timed_audio_transcript` for the `analyze_audio` tool | Speech segments transcribed one by one, with times; the run is kept in the chat's folder |
| `VideoAnalyzeAgent` | `analyze_video(file:, attachment_id:, fps:, query:, session:, detailed:)` | Frames from `extract_frames.py` in the Python container; at most 50 frames (20 for Claude) per request; transcript of the audio track; `detailed` splits long videos into up to 5 parts of up to 10 minutes |
| `AudioAnalysisAgent` | `analyze(audio_path:, prompt:, model:)` | Qualitative music analysis with Gemini; used only by the Gemini variant of Music Analyst |

The media agents call the providers directly with the `http` gem, retry a failed request once, and return a string starting with `ERROR:` on failure.

Attachments are taken by id only within a request. When a message is accepted, `handle_ws_streaming` checks the `attachments` it carries against the ledger (`Attachments.refs_for_message!`: a ready attachment of this chat, listed once, role `input`, at most 10; purpose, name and size come from the ledger), records them on the user message with its `request_id` (`q_…`) (the model is told about them by the provider helper, see `vendor_interface_contract.md`), and fixes a `Workspace::RequestContext` for the thread that answers: the chat and the attachments of this message and earlier messages of the same chat. `analyze_video` and `analyze_audio` resolve an id (also one passed in `file`/`audio`) with `Attachments.resolve_for_request!`, which refuses an id the request does not allow, any id without a request, and one whose chat is no longer the session's. This keeps tools from using a file that was uploaded but not sent, or whose id is only written in a message; it is not a boundary for secrets (code the model runs in the Python container can read the shared folder).

### Shared Tool Groups

| Group | Tool | Module |
|---|---|---|
| `:image_analysis` | `analyze_image` | `MonadicSharedTools::ImageAnalysis` |
| `:audio_transcription` | `analyze_audio` | `MonadicSharedTools::AudioTranscription` |
| `:video_analysis` | `analyze_video` | `MonadicSharedTools::VideoAnalysis` |

They are `conditional` groups in `shared_tools/registry.rb`; `available_when` calls the module's `available?`. Apps add them with `import_shared_tools :image_analysis, visibility: "conditional"`.

## Code Generation

| Module | Method | Default model | Timeout |
|---|---|---|---|
| `OpenAICodeAgent` | `call_openai_code(prompt:, app_name:, timeout:, model:)` | `ModelSpec.default_code_model("openai")`, Responses API | `OPENAI_CODE_TIMEOUT`, default 1200 s |
| `ClaudeCodeAgent` | `call_claude_code(prompt:, app_name:, max_tokens:, temperature:, reasoning_effort:)` | `ModelSpec.default_code_model("anthropic")` | — |
| `GrokCodeAgent` | `call_grok_code(prompt:, app_name:, timeout:, model:)` | `ModelSpec.default_code_model("xai")` | `GROK_CODE_TIMEOUT`, default 300 s |

Each is used only by the app variants of its own provider: Code Interpreter, Coding Assistant, Jupyter Notebook and Research Assistant tools, and AutoForge (wired in `apps/auto_forge/auto_forge_tools.rb`). They do not retry.

## Conversation Agents

- **`SecondOpinionAgent`**: `second_opinion_agent(user_query:, agent_response:, provider:, model:, session:)` asks one provider; `parallel_second_opinions(…, providers:)` asks several in threads, each with its own helper instance. Text is masked by the Privacy Filter pipeline first when it is on.
- **`ContextExtractorAgent`**: `extract_context(session, user_message, assistant_response, provider, schema, language)` builds the Session Context after a response; `WebSocketHelper` includes the module. It calls the API directly, not through `send_query`, so it does not re-enter the WebSocket flow.
- **`AIUserAgent`**: `process_ai_user(session, params)` writes the next user message with the provider's chat app and default model.

## Adding a Media Agent

1. Add the capability and its providers to `ProviderCapabilities::CAPABILITIES` (only providers with a working request path).
2. Write the agent module: resolve the provider with `ProviderCapabilities.resolve`, take the model from `ModelSpec`, call the provider, return `ERROR: …` on failure.
3. Include it in `MonadicApp` if many apps use it.
4. Add a module under `lib/monadic/shared_tools/` with `available?` and the tool definitions, register the group in `registry.rb` (`visibility: 'conditional'`, `available_when`), and require it in `dsl.rb`.
5. Import the group in the MDSL files of the apps that use it.
6. Add specs under `spec/unit/agents/`: provider resolution and its errors, request format per provider, file checks.

## Tests

`spec/unit/agents/` has a spec per agent.
