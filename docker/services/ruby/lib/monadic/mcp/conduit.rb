# frozen_string_literal: true

require 'json'
require_relative 'cost_guard'
require_relative 'job_store'
require_relative 'conduit_agent'
require_relative '../agents/second_opinion_agent'
require_relative '../agents/image_analysis_agent'
require_relative '../agents/audio_transcription_agent'
require_relative '../agents/audio_analysis_agent'
require_relative '../agents/video_analyze_agent'
require_relative '../agents/openai_code_agent'
require_relative '../agents/claude_code_agent'
require_relative '../agents/grok_code_agent'

module Monadic
  module MCP
    # Monadic Conduit — the capability surface exposed to external agentic CLIs
    # (e.g. Claude Code) over MCP.
    #
    # Design principle (the "first principle"): Conduit does NOT re-publish the
    # app-specific tools (the former `app__tool` surface). It publishes a small,
    # stable set of *capabilities* over Monadic's data, environment, model access
    # and modalities — leaving orchestration to the calling CLI agent.
    #
    # Phase 0 tools are read-only, side-effect-free and zero-cost:
    #   - monadic_status        : backend + dependent-container readiness
    #   - monadic_list_models   : provider × model + capabilities (from the SSOT)
    #
    # Phase 1 introduces the first provider-spending capability:
    #   - monadic_query         : single-provider, context-aware query
    #
    # Every spending tool goes through CostGuard (design §5): the platform
    # reserves a token budget BEFORE the call and records usage AFTER, so a
    # runaway CLI agent is refused rather than trusted. Provider Independence is
    # preserved by borrowing a real per-provider app instance from APPS and
    # calling its own send_query (no cross-provider routing).
    module Conduit
      module_function

      # Default cap on a single query's output tokens when the caller omits one.
      DEFAULT_MAX_OUTPUT = 4096

      # Bounds for parallel fan-out.
      MAX_PARALLEL_PROVIDERS = 5
      # Upper bound for the explicit `targets` fan-out (lets a caller compare
      # many specific models, including several from the same provider).
      MAX_PARALLEL_TARGETS = 12
      PARALLEL_TIMEOUT = 180

      # Memoized host CLASSES (see provider_host); a fresh instance is built per
      # call so concurrent same-provider queries never share one host.
      @provider_host_classes = {}
      @hosts_mutex = Mutex.new

      # Public: MCP tool definitions for `tools/list`.
      def tools
        registry.map do |tool|
          {
            name: tool[:name],
            description: tool[:description],
            inputSchema: tool[:input_schema]
          }
        end
      end

      # Public: whether a tool name belongs to the Conduit surface.
      def tool?(name)
        registry.any? { |tool| tool[:name] == name }
      end

      # Public: invoke a Conduit tool. Returns a Ruby Hash (structured result);
      # the MCP server wraps it as both text and structuredContent.
      def call(name, arguments = {})
        tool = registry.find { |t| t[:name] == name }
        raise "Unknown Conduit tool: #{name}" unless tool

        send(tool[:handler], arguments || {})
      end

      # ---- Tool registry --------------------------------------------------

      def registry
        [
          {
            name: "monadic_status",
            description: "Report Monadic Chat backend health: version, execution mode, " \
                         "MCP server state, which providers have API keys configured, and " \
                         "which dependent containers are running. Read-only.",
            input_schema: { type: "object", properties: {}, additionalProperties: false },
            handler: :handle_status
          },
          {
            name: "monadic_list_models",
            description: "List available providers and their models with capabilities " \
                         "(context window, max output, vision/tool/reasoning support) drawn " \
                         "from Monadic's model specification. Read-only; no provider API call. " \
                         "Optionally filter by provider, or include deprecated models.",
            input_schema: {
              type: "object",
              properties: {
                provider: {
                  type: "string",
                  description: "Optional provider filter (e.g. openai, anthropic, gemini, " \
                               "cohere, mistral, deepseek, xai, ollama). Aliases like " \
                               "'claude', 'google', 'grok' are accepted."
                },
                include_deprecated: {
                  type: "boolean",
                  description: "Include models marked deprecated. Defaults to false."
                }
              },
              additionalProperties: false
            },
            handler: :handle_list_models
          },
          {
            name: "monadic_query",
            description: "Send a one-shot query to a specific provider's chat model and " \
                         "return the text response. Uses Monadic's own provider helpers " \
                         "(your local API keys, data stays local). Spends provider tokens; " \
                         "every call is gated by a platform-side token budget (see " \
                         "monadic_status.conduit_budget). Provide either `message` (a single " \
                         "user prompt) or `messages` (a full role/content conversation).",
            input_schema: {
              type: "object",
              properties: {
                provider: {
                  type: "string",
                  description: "Provider to query (openai, anthropic, gemini, cohere, " \
                               "mistral, deepseek, xai, ollama). Aliases (claude/google/grok) " \
                               "are accepted."
                },
                message: {
                  type: "string",
                  description: "A single user prompt. Use this OR `messages`, not both."
                },
                messages: {
                  type: "array",
                  description: "A full conversation as role/content turns. Use this OR `message`.",
                  items: {
                    type: "object",
                    properties: {
                      role: { type: "string", description: "user | assistant | system" },
                      content: { type: "string", description: "Message text." }
                    },
                    required: ["role", "content"]
                  }
                },
                system: {
                  type: "string",
                  description: "Optional system prompt prepended to the request."
                },
                model: {
                  type: "string",
                  description: "Optional model id. Defaults to the provider's chat default. " \
                               "Call monadic_list_models to discover valid model ids."
                },
                max_tokens: {
                  type: "integer",
                  description: "Optional cap on output tokens (default #{DEFAULT_MAX_OUTPUT}). " \
                               "Note: reasoning/thinking models spend this cap on internal " \
                               "reasoning before any visible output, so set it generously " \
                               "(e.g. >= 1000) or the answer can come back truncated."
                },
                temperature: {
                  type: "number",
                  description: "Optional sampling temperature (ignored by models that reject it)."
                },
                knowledge_base: {
                  type: "string",
                  description: "Optional KB namespace. When set, the latest user message is " \
                               "used to retrieve relevant chunks from the local Knowledge Base " \
                               "and inject them as grounding context (data stays local)."
                },
                privacy: {
                  type: "boolean",
                  description: "When true, mask PII in the request before sending and restore " \
                               "it in the response (requires the privacy container; fails closed)."
                }
              },
              required: ["provider"],
              additionalProperties: false
            },
            handler: :handle_query
          },
          {
            name: "monadic_parallel_query",
            description: "GENERATE answers: fan the same query out to several models concurrently " \
                         "and return all of their fresh, independent responses together (each " \
                         "labeled with its `index`), so a CLI agent can compare diverse answers " \
                         "without writing its own concurrency. This PRODUCES new answers — it " \
                         "does not score an existing one; to grade an answer you already have, " \
                         "use `monadic_second_opinion` instead. Use `targets` to pick specific " \
                         "models (any mix, including several from the same provider, up to " \
                         "#{MAX_PARALLEL_TARGETS}), or `providers` for distinct providers on " \
                         "their chat defaults. Each sub-query spends tokens (budget-gated). " \
                         "Provide `message` or `messages`.",
            input_schema: {
              type: "object",
              properties: {
                targets: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_TARGETS} explicit {provider, model} targets. " \
                               "Duplicates and repeated providers are allowed. Use this OR " \
                               "`providers`.",
                  items: {
                    type: "object",
                    properties: {
                      provider: { type: "string", description: "Provider name." },
                      model: {
                        type: "string",
                        description: "Optional model id (chat default if omitted). Call " \
                                     "monadic_list_models to discover valid model ids."
                      }
                    },
                    required: ["provider"]
                  }
                },
                providers: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_PROVIDERS} distinct provider names. Use this OR " \
                               "`targets`.",
                  items: { type: "string" }
                },
                message: {
                  type: "string",
                  description: "A single user prompt sent to every provider. Use this OR `messages`."
                },
                messages: {
                  type: "array",
                  description: "A full conversation sent to every provider. Use this OR `message`.",
                  items: {
                    type: "object",
                    properties: {
                      role: { type: "string", description: "user | assistant | system" },
                      content: { type: "string", description: "Message text." }
                    },
                    required: ["role", "content"]
                  }
                },
                models: {
                  type: "object",
                  description: "Optional per-provider model override, keyed by provider name. " \
                               "Providers without an entry use their chat default."
                },
                system: {
                  type: "string",
                  description: "Optional system prompt applied to every provider."
                },
                max_tokens: {
                  type: "integer",
                  description: "Optional per-provider output cap (default #{DEFAULT_MAX_OUTPUT}). " \
                               "Reasoning/thinking models spend this cap on internal reasoning " \
                               "before visible output — set it generously (e.g. >= 1000) or an " \
                               "answer can return truncated (see each result's possibly_incomplete)."
                },
                temperature: {
                  type: "number",
                  description: "Optional sampling temperature applied to every provider."
                },
                knowledge_base: {
                  type: "string",
                  description: "Optional KB namespace to ground every provider's answer."
                },
                privacy: {
                  type: "boolean",
                  description: "When true, mask PII before sending to every provider and " \
                               "restore it in each response (fails closed)."
                }
              },
              required: [],
              additionalProperties: false
            },
            handler: :handle_parallel_query
          },
          {
            name: "monadic_second_opinion",
            description: "GRADE an answer: ask one or more providers to critically evaluate a " \
                         "query/response pair you ALREADY have and return a validity score " \
                         "(1-10) plus critique — Monadic's second-opinion sub-agent. This SCORES " \
                         "a given answer (both `user_query` and `agent_response` are required); " \
                         "it does not generate fresh answers — to produce new answers across " \
                         "models, use `monadic_parallel_query` instead. Use it to cross-check an " \
                         "answer (your own or another model's) before trusting it. Give " \
                         "`provider` for a single evaluator, or `providers` " \
                         "(2-#{MAX_PARALLEL_PROVIDERS}) to verify in parallel. Spends tokens; " \
                         "gated by the platform token budget.",
            input_schema: {
              type: "object",
              properties: {
                user_query: {
                  type: "string",
                  description: "The original question or prompt being evaluated."
                },
                agent_response: {
                  type: "string",
                  description: "The response whose correctness should be verified."
                },
                provider: {
                  type: "string",
                  description: "Single evaluator provider. Omit to default to OpenAI. " \
                               "Use this OR `providers`."
                },
                providers: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_PROVIDERS} providers to verify in parallel. " \
                               "Use this OR `provider`.",
                  items: { type: "string" }
                },
                model: {
                  type: "string",
                  description: "Optional model override for the single-provider form."
                }
              },
              required: ["user_query", "agent_response"],
              additionalProperties: false
            },
            handler: :handle_second_opinion
          },
          {
            name: "monadic_confidence",
            description: "ASSESS confidence by AGREEMENT: fan a question out to several DIVERSE " \
                         "(cross-provider) models, then judge how much their independent answers " \
                         "AGREE. Cross-provider agreement is a calibrated proxy for trustworthiness " \
                         "— on labeled benchmarks, when a diverse panel agreed the answer was " \
                         "almost always correct, and when it scattered correctness fell to a " \
                         "coin-flip. Use it to catch overconfident single-model hallucination: a " \
                         "lone model always sounds sure, but disagreement across independent models " \
                         "is a real uncertainty signal. Returns a confidence level (high/medium/low) " \
                         "+ what they agree on, the points of disagreement, the raw responses, and a " \
                         "recommendation (trust/verify/escalate). For a meaningful signal use " \
                         "DISTINCT providers (same-provider agreement has correlated errors). Each " \
                         "sub-query plus one judge call spends tokens (budget-gated). Provide " \
                         "`message` or `messages`.",
            input_schema: {
              type: "object",
              properties: {
                targets: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_TARGETS} explicit {provider, model} panel members. " \
                               "Prefer DISTINCT providers for an independent signal. Use this OR " \
                               "`providers`.",
                  items: {
                    type: "object",
                    properties: {
                      provider: { type: "string", description: "Provider name." },
                      model: { type: "string", description: "Optional model id (chat default if omitted)." }
                    },
                    required: ["provider"]
                  }
                },
                providers: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_PROVIDERS} distinct provider names (the diverse " \
                               "panel). Use this OR `targets`.",
                  items: { type: "string" }
                },
                message: {
                  type: "string",
                  description: "A single question sent to every panel member. Use this OR `messages`."
                },
                messages: {
                  type: "array",
                  description: "A full conversation sent to every panel member. Use this OR `message`.",
                  items: {
                    type: "object",
                    properties: {
                      role: { type: "string", description: "user | assistant | system" },
                      content: { type: "string", description: "Message text." }
                    },
                    required: ["role", "content"]
                  }
                },
                judge: {
                  type: "object",
                  description: "Optional {provider, model} for the consensus judge (defaults to " \
                               "OpenAI chat default). The judge reads the panel's responses " \
                               "ANONYMIZED, so it cannot favor its own.",
                  properties: {
                    provider: { type: "string" },
                    model: { type: "string" }
                  }
                },
                review_answer: {
                  type: "string",
                  description: "Optional EXISTING answer to corroborate against the panel (e.g. a " \
                               "response you already have). When given, the judge also reports " \
                               "whether this answer aligns with the panel's consensus or is an " \
                               "outlier (`corroboration`: corroborated | partial | disputed)."
                },
                system: { type: "string", description: "Optional system prompt for every panel member." },
                max_tokens: {
                  type: "integer",
                  description: "Optional per-member output cap (default #{DEFAULT_MAX_OUTPUT})."
                },
                temperature: { type: "number", description: "Optional sampling temperature for the panel." },
                knowledge_base: {
                  type: "string",
                  description: "Optional KB namespace to ground every panel member's answer."
                },
                privacy: {
                  type: "boolean",
                  description: "When true, mask PII before sending to every member and restore it (fails closed)."
                }
              },
              required: [],
              additionalProperties: false
            },
            handler: :handle_confidence
          },
          {
            name: "monadic_search_kb",
            description: "Semantic search over a local PDF Knowledge Base (Qdrant + " \
                         "multilingual-e5 embeddings). Returns the most relevant chunks for a " \
                         "query. Runs entirely on your machine (no provider API, no token " \
                         "cost). Use it to ground answers in your own documents.",
            input_schema: {
              type: "object",
              properties: {
                query: { type: "string", description: "The text to search for." },
                knowledge_base: {
                  type: "string",
                  description: "KB namespace (app key). Defaults to 'global' (the generic " \
                               "PDF upload namespace)."
                },
                top_n: {
                  type: "integer",
                  description: "Number of results to return (1-50, default 5)."
                },
                level: {
                  type: "string",
                  description: "'item' for text chunks (default) or 'doc' for document-level hits."
                }
              },
              required: ["query"],
              additionalProperties: false
            },
            handler: :handle_search_kb
          },
          {
            name: "monadic_list_kb",
            description: "List the documents stored in a local PDF Knowledge Base namespace.",
            input_schema: {
              type: "object",
              properties: {
                knowledge_base: {
                  type: "string",
                  description: "KB namespace (app key). Defaults to 'global'."
                }
              },
              additionalProperties: false
            },
            handler: :handle_list_kb
          },
          {
            name: "monadic_import_kb",
            description: "Import a document into a local PDF Knowledge Base namespace " \
                         "(chunk + embed + store). Provide `text` for raw text (no extra " \
                         "containers needed) or `path` to a local .pdf file (extracted via the " \
                         "python container). Embeddings are computed locally — no provider " \
                         "token cost. Synchronous.",
            input_schema: {
              type: "object",
              properties: {
                title: { type: "string", description: "Title for the stored document." },
                text: {
                  type: "string",
                  description: "Raw text to import. Use this OR `path`."
                },
                path: {
                  type: "string",
                  description: "Absolute path to a local .pdf file to import. Use this OR `text`."
                },
                knowledge_base: {
                  type: "string",
                  description: "KB namespace (app key). Defaults to 'global'."
                }
              },
              required: ["title"],
              additionalProperties: false
            },
            handler: :handle_import_kb
          },
          {
            name: "monadic_analyze_image",
            description: "Analyze an image with a vision model and return a text description/" \
                         "answer. Give a `prompt` (what to look at) and an image `path` on the " \
                         "shared volume (~/monadic/data). Uses your own API keys; spends provider " \
                         "tokens (budget-gated). A vision-capable provider is chosen automatically " \
                         "unless you pass one.",
            input_schema: {
              type: "object",
              properties: {
                prompt: {
                  type: "string",
                  description: "What to ask about the image (e.g. 'Describe this diagram')."
                },
                path: {
                  type: "string",
                  description: "Image path: absolute, or relative to the shared volume " \
                               "(~/monadic/data). Formats: jpg, png, gif, webp (max 10MB)."
                },
                provider: {
                  type: "string",
                  description: "Optional preferred vision provider (openai, anthropic/claude, " \
                               "gemini/google, xai/grok). Falls back to the first available."
                }
              },
              required: ["prompt", "path"],
              additionalProperties: false
            },
            handler: :handle_analyze_image
          },
          {
            name: "monadic_transcribe_audio",
            description: "Transcribe an audio file to text (speech-to-text) using a provider's " \
                         "STT API. Give an audio `path` on the shared volume (~/monadic/data). " \
                         "Uses your own API keys; spends provider tokens (budget-gated). A " \
                         "capable provider is chosen automatically unless you pass one.",
            input_schema: {
              type: "object",
              properties: {
                path: {
                  type: "string",
                  description: "Audio path: absolute, or relative to the shared volume " \
                               "(~/monadic/data). Max 25MB."
                },
                language: {
                  type: "string",
                  description: "Optional ISO language code hint (e.g. 'en', 'ja')."
                },
                model: {
                  type: "string",
                  description: "Optional STT model override."
                },
                provider: {
                  type: "string",
                  description: "Optional preferred provider (openai, gemini/google). Falls " \
                               "back to the first available."
                }
              },
              required: ["path"],
              additionalProperties: false
            },
            handler: :handle_transcribe_audio
          },
          {
            name: "monadic_analyze_audio",
            description: "Analyze an audio file qualitatively (e.g. describe/critique music or " \
                         "speech) with Gemini. Give an audio `path` on the shared volume " \
                         "(~/monadic/data) and a `prompt` for what to analyze. This is " \
                         "interpretive analysis, not transcription (use monadic_transcribe_audio " \
                         "for text). Uses your own API keys; spends provider tokens (budget-gated).",
            input_schema: {
              type: "object",
              properties: {
                prompt: {
                  type: "string",
                  description: "What to analyze (e.g. 'Critique this performance')."
                },
                path: {
                  type: "string",
                  description: "Audio path: absolute, or relative to the shared volume " \
                               "(~/monadic/data)."
                }
              },
              required: ["prompt", "path"],
              additionalProperties: false
            },
            handler: :handle_analyze_audio
          },
          {
            name: "monadic_analyze_video",
            description: "Analyze a video file by extracting frames and querying a vision model, " \
                         "plus transcribing its audio. Give a video `path` on the shared volume " \
                         "(~/monadic/data) and an optional `query`. Requires the Python container " \
                         "(frame extraction). Uses your own API keys; spends provider tokens " \
                         "(budget-gated). Can take a while — runnable via monadic_submit.",
            input_schema: {
              type: "object",
              properties: {
                path: {
                  type: "string",
                  description: "Video filename on the shared volume (~/monadic/data)."
                },
                query: {
                  type: "string",
                  description: "Optional question about the video (default: describe what happens)."
                },
                fps: {
                  type: "number",
                  description: "Optional frames-per-second to sample (default 1)."
                }
              },
              required: ["path"],
              additionalProperties: false
            },
            handler: :handle_analyze_video
          },
          {
            name: "monadic_speak",
            description: "Synthesize speech from text (text-to-speech) and save an audio file " \
                         "to the shared volume (~/monadic/data). Returns the saved filename. " \
                         "Uses your own API keys; spends provider tokens (budget-gated). " \
                         "Providers: openai (default), gemini/google, elevenlabs. " \
                         "ElevenLabs requires an explicit `voice` (voice_id).",
            input_schema: {
              type: "object",
              properties: {
                text: {
                  type: "string",
                  description: "The text to speak."
                },
                provider: {
                  type: "string",
                  description: "TTS provider: openai (default), gemini/google, elevenlabs."
                },
                voice: {
                  type: "string",
                  description: "Optional voice id. Defaults: openai='alloy', gemini='zephyr'. " \
                               "ElevenLabs has no default — pass a voice_id from your account."
                },
                speed: {
                  type: "number",
                  description: "Optional speaking rate (0.25–4.0, default 1.0)."
                },
                language: {
                  type: "string",
                  description: "Optional ISO language code (e.g. 'en', 'ja') or 'auto' (default)."
                },
                instructions: {
                  type: "string",
                  description: "Optional style/delivery instructions (openai)."
                }
              },
              required: ["text"],
              additionalProperties: false
            },
            handler: :handle_speak
          },
          {
            name: "monadic_generate_code",
            description: "Generate code with a provider's dedicated code agent (OpenAI Code, " \
                         "Claude Code, or Grok Code). Give a `prompt` describing the task; " \
                         "returns the generated code. Uses your own API keys; spends provider " \
                         "tokens (budget-gated). LONG-RUNNING (up to ~20 min for complex tasks) " \
                         "— run this via monadic_submit and poll, so it doesn't block the " \
                         "platform. A configured provider is chosen automatically unless you " \
                         "pass one.",
            input_schema: {
              type: "object",
              properties: {
                prompt: {
                  type: "string",
                  description: "The coding task / instruction for the code agent."
                },
                provider: {
                  type: "string",
                  description: "Optional preferred provider: openai, anthropic/claude, xai/grok. " \
                               "Falls back to the first configured one."
                }
              },
              required: ["prompt"],
              additionalProperties: false
            },
            handler: :handle_generate_code
          },
          {
            name: "monadic_generate_image",
            description: "Generate an image from a text prompt and save it to the shared " \
                         "volume (~/monadic/data). Returns the saved filename(s). Uses your own " \
                         "API keys; spends provider tokens (budget-gated). Providers: openai " \
                         "(default), grok/xai, gemini/google. Can take a while — run via " \
                         "monadic_submit and poll for progress.",
            input_schema: {
              type: "object",
              properties: {
                prompt: { type: "string", description: "What to draw." },
                provider: {
                  type: "string",
                  description: "openai (default), grok/xai, gemini/google."
                },
                aspect_ratio: {
                  type: "string",
                  description: "Optional aspect ratio for grok/gemini, e.g. '16:9'."
                },
                size: {
                  type: "string",
                  description: "Optional pixel size for openai, e.g. '1024x1024'."
                }
              },
              required: ["prompt"],
              additionalProperties: false
            },
            handler: :handle_generate_image
          },
          {
            name: "monadic_generate_video",
            description: "Generate a video from a text prompt (optionally image-to-video) and " \
                         "save it to the shared volume (~/monadic/data). Returns the saved " \
                         "filename. Uses your own API keys; spends provider tokens (budget-" \
                         "gated). Providers: gemini/veo (default), grok/xai. LONG-RUNNING " \
                         "(minutes) — run via monadic_submit and poll for progress.",
            input_schema: {
              type: "object",
              properties: {
                prompt: { type: "string", description: "What the video should show." },
                provider: { type: "string", description: "gemini/veo (default), grok/xai." },
                aspect_ratio: { type: "string", description: "Optional aspect ratio, e.g. '16:9'." },
                duration: { type: "number", description: "Optional duration in seconds." },
                image_path: {
                  type: "string",
                  description: "Optional source image (filename on the shared volume) for " \
                               "image-to-video."
                }
              },
              required: ["prompt"],
              additionalProperties: false
            },
            handler: :handle_generate_video
          },
          {
            name: "monadic_generate_music",
            description: "Generate music/audio from a text prompt (Lyria) and save it to the " \
                         "shared volume (~/monadic/data). Returns the saved filename. Uses your " \
                         "own API keys; spends provider tokens (budget-gated). LONG-RUNNING — " \
                         "run via monadic_submit and poll for progress.",
            input_schema: {
              type: "object",
              properties: {
                prompt: { type: "string", description: "Description of the music to generate." },
                format: { type: "string", description: "Optional output format (e.g. 'mp3', 'wav')." }
              },
              required: ["prompt"],
              additionalProperties: false
            },
            handler: :handle_generate_music
          },
          {
            name: "monadic_agent",
            description: "Run a bounded autonomous agent that USES TOOLS recursively to do a " \
                         "task: it can call a tool, read the result, reason, and call more tools " \
                         "until done (e.g. search the web, read a page, search again), then " \
                         "return a final answer. Tools come from named groups (default " \
                         "['web_search_tools']); only safe read-only groups are permitted. " \
                         "Termination is guaranteed (max 20 tool calls/turn + stuck-loop " \
                         "detection). Uses your own API keys; spends provider tokens " \
                         "(budget-gated). LONG-RUNNING — run via monadic_submit and poll.",
            input_schema: {
              type: "object",
              properties: {
                task: {
                  type: "string",
                  description: "The instruction for the agent (what to accomplish)."
                },
                tools: {
                  type: "array",
                  description: "Optional tool-group names to grant. Default ['web_search_tools']. " \
                               "Allowed (read-only): web_search_tools, file_reading, " \
                               "image_analysis, video_analysis, audio_transcription, " \
                               "session_context, verification, planning.",
                  items: { type: "string" }
                },
                provider: {
                  type: "string",
                  description: "Optional provider whose model runs the loop (openai default, " \
                               "anthropic/claude, gemini/google, xai/grok)."
                }
              },
              required: ["task"],
              additionalProperties: false
            },
            handler: :handle_agent
          },
          {
            name: "monadic_submit",
            description: "Run another Conduit tool as a background job and return a job_id " \
                         "immediately, without blocking. Use this for long or blocking tools " \
                         "(e.g. monadic_speak, and future media-generation / code-agent tools) " \
                         "so they don't tie up the platform. Poll with monadic_poll, stop with " \
                         "monadic_cancel. Concurrency is capped; job-control tools cannot be " \
                         "submitted. Budget rules still apply when the job runs.",
            input_schema: {
              type: "object",
              properties: {
                tool: {
                  type: "string",
                  description: "Name of the Conduit tool to run in the background " \
                               "(e.g. 'monadic_speak')."
                },
                arguments: {
                  type: "object",
                  description: "Arguments object passed to that tool, exactly as you would " \
                               "pass them in a direct call."
                }
              },
              required: ["tool"],
              additionalProperties: false
            },
            handler: :handle_submit
          },
          {
            name: "monadic_poll",
            description: "Check a background job by `job_id`. Returns its status " \
                         "(running/done/error/cancelled) and, when finished, the tool's result " \
                         "or error. Jobs are forgotten a while after they finish.",
            input_schema: {
              type: "object",
              properties: {
                job_id: { type: "string", description: "The job id returned by monadic_submit." }
              },
              required: ["job_id"],
              additionalProperties: false
            },
            handler: :handle_poll
          },
          {
            name: "monadic_cancel",
            description: "Cancel a running background job by `job_id` (kill switch). Finished " \
                         "jobs are returned unchanged.",
            input_schema: {
              type: "object",
              properties: {
                job_id: { type: "string", description: "The job id to cancel." }
              },
              required: ["job_id"],
              additionalProperties: false
            },
            handler: :handle_cancel
          },
          {
            name: "monadic_jobs",
            description: "List known background jobs (id, tool, status, timestamps) so you can " \
                         "track or clean up in-flight work.",
            input_schema: {
              type: "object",
              properties: {},
              additionalProperties: false
            },
            handler: :handle_jobs
          }
        ]
      end

      # ---- Handlers -------------------------------------------------------

      def handle_status(_arguments)
        {
          backend: {
            name: "monadic-chat",
            version: (defined?(Monadic::VERSION) ? Monadic::VERSION : "unknown"),
            mode: execution_mode
          },
          mcp: safe_mcp_status,
          conduit_budget: CostGuard.status,
          providers: provider_readiness,
          containers: container_readiness
        }
      end

      def handle_list_models(arguments)
        include_deprecated = truthy?(arguments["include_deprecated"] || arguments[:include_deprecated])
        requested = (arguments["provider"] || arguments[:provider]).to_s.strip

        provider_keys = MonadicDSL::ProviderConfig::PROVIDER_INFO.keys
        if !requested.empty?
          canonical = MonadicDSL::ProviderConfig.new(requested).standard_key
          provider_keys = provider_keys.select { |k| k == canonical }
        end

        providers = provider_keys.map do |provider|
          provider_models_entry(provider, include_deprecated)
        end

        { providers: providers }
      end

      def handle_query(arguments)
        provider_arg = (arguments["provider"] || arguments[:provider]).to_s.strip
        raise ArgumentError, "provider is required" if provider_arg.empty?

        canonical = MonadicDSL::ProviderConfig.new(provider_arg).standard_key

        messages = normalize_messages(arguments)
        raise ArgumentError, "provide either `message` or `messages`" if messages.empty?

        result = execute_query(
          provider: canonical,
          messages: messages,
          system: (arguments["system"] || arguments[:system]).to_s,
          model: (arguments["model"] || arguments[:model]),
          max_output: (arguments["max_tokens"] || arguments[:max_tokens]),
          temperature: (arguments["temperature"] || arguments[:temperature]),
          knowledge_base: (arguments["knowledge_base"] || arguments[:knowledge_base]),
          privacy: (arguments["privacy"] || arguments[:privacy])
        )
        result.merge(budget: CostGuard.status)
      end

      def handle_parallel_query(arguments)
        messages = normalize_messages(arguments)
        raise ArgumentError, "provide either `message` or `messages`" if messages.empty?

        indexed = fan_out_panel(messages, resolve_parallel_targets(arguments), arguments)
        { results: indexed, budget: CostGuard.status }
      end

      # Shared fan-out: run the same conversation against every target and return
      # the results indexed (so duplicate provider+model targets stay
      # distinguishable). Used by both parallel_query and confidence. `sequential`
      # forces one-at-a-time execution (required when a target is a single local
      # server — concurrent requests get dropped, ensemble-experiment gotcha).
      def fan_out_panel(messages, targets, arguments, sequential: false, temperature: nil)
        system = (arguments["system"] || arguments[:system]).to_s
        max_output = arguments["max_tokens"] || arguments[:max_tokens]
        temperature ||= arguments["temperature"] || arguments[:temperature]
        knowledge_base = arguments["knowledge_base"] || arguments[:knowledge_base]
        privacy = arguments["privacy"] || arguments[:privacy]

        runner = lambda do |target|
          execute_query(
            provider: target[:provider], messages: messages, system: system,
            model: target[:model], max_output: max_output, temperature: temperature,
            knowledge_base: knowledge_base, privacy: privacy
          )
        end

        results =
          if sequential
            targets.map do |t|
              runner.call(t)
            rescue StandardError => e
              { provider: t[:provider], model: t[:model], success: false, error: "❌ #{e.class}: #{e.message}" }
            end
          else
            run_in_parallel(targets, &runner)
          end
        results.each_with_index.map { |r, i| (r || {}).merge(index: i) }
      end

      # Build the list of {provider, model} targets to fan out to, from EITHER:
      #   - `targets`: an explicit array of {provider, model?} (any count up to
      #     MAX_PARALLEL_TARGETS, duplicates and same-provider repeats allowed);
      #   - `providers`: 2-MAX_PARALLEL_PROVIDERS provider names with an optional
      #     per-provider `models` map (de-duplicated; backward compatible).
      def resolve_parallel_targets(arguments)
        explicit = arguments["targets"] || arguments[:targets]
        if explicit
          unless explicit.is_a?(Array) && explicit.size.between?(2, MAX_PARALLEL_TARGETS)
            raise ArgumentError,
                  "targets must be an array of 2-#{MAX_PARALLEL_TARGETS} {provider, model} objects"
          end
          return explicit.map do |t|
            raise ArgumentError, "each target needs a provider" unless t.is_a?(Hash)

            provider = (t["provider"] || t[:provider]).to_s
            raise ArgumentError, "each target needs a provider" if provider.empty?

            { provider: MonadicDSL::ProviderConfig.new(provider).standard_key,
              model: (t["model"] || t[:model]) }
          end
        end

        providers_arg = arguments["providers"] || arguments[:providers]
        unless providers_arg.is_a?(Array) && providers_arg.size.between?(2, MAX_PARALLEL_PROVIDERS)
          raise ArgumentError,
                "provide `targets`, or `providers` (an array of 2-#{MAX_PARALLEL_PROVIDERS} names)"
        end

        models = arguments["models"] || arguments[:models] || {}
        providers_arg.each_with_object([]) do |raw, acc|
          original = raw.to_s
          canonical = MonadicDSL::ProviderConfig.new(original).standard_key
          next if acc.any? { |t| t[:provider] == canonical }

          acc << { provider: canonical, model: (models[original] || models[canonical]) }
        end
      end

      # ---- Confidence via agreement --------------------------------------

      # Map a 0-1 consensus score to a confidence band + recommended action.
      # Calibrated against labeled benchmarks (validate_confidence.rb): a
      # unanimous DIVERSE panel was ~always correct, a split panel ~coin-flip.
      CONFIDENCE_BANDS = [
        [0.8, "high",   "trust"],
        [0.5, "medium", "verify"]
      ].freeze

      def handle_confidence(arguments)
        messages = normalize_messages(arguments)
        raise ArgumentError, "provide either `message` or `messages`" if messages.empty?

        # Panel: the caller's explicit choice, OR auto-select via the degradation
        # ladder when none is given (the chat-UI verify button takes this path).
        # When the ladder reports it CANNOT measure agreement honestly (e.g. a
        # single deterministic model), refuse rather than fan out and fake it.
        explicit = arguments["targets"] || arguments[:targets] ||
                   arguments["providers"] || arguments[:providers]
        temperature_override = nil
        if explicit
          targets = resolve_parallel_targets(arguments)
        else
          plan = select_confidence_panel
          if plan[:mode] == :unavailable
            return { confidence: "unavailable", score: nil, consensus: "", disagreements: [],
                     recommendation: "verify", note: plan[:reason], responses: [],
                     budget: CostGuard.status }
          end
          targets = plan[:targets]
          if plan[:mode] == :within_provider
            # Self-consistency: run the ONE model K times. Force a sampling
            # temperature so the samples can actually diverge — at temperature 0
            # they would be identical and fake a unanimous (false) signal.
            targets *= plan[:samples].to_i.clamp(2, 8)
            temperature_override = 0.8
          end
        end

        # A single local server (Ollama) drops concurrent requests, so its panel
        # must run sequentially (ensemble-experiment gotcha).
        sequential = targets.any? { |t| single_local_server?(t[:provider]) }

        # (1) Fan out to the panel (shared machinery; sequential when required).
        responses = fan_out_panel(messages, targets, arguments,
                                  sequential: sequential, temperature: temperature_override)
        usable = responses.select { |r| r[:success] && !r[:text].to_s.strip.empty? }

        if usable.size < 2
          return {
            confidence: "unknown", score: nil, consensus: "", disagreements: [],
            recommendation: "verify",
            note: "Need >= 2 successful responses to assess agreement (got #{usable.size}).",
            responses: responses, budget: CostGuard.status
          }
        end

        # (2) Judge consensus over ANONYMIZED responses (no provider labels, so
        # the judge cannot favor its own).
        question = (messages.reverse.find { |m| m["role"] == "user" } || messages.last)&.dig("content").to_s
        review_answer = (arguments["review_answer"] || arguments[:review_answer]).to_s
        verdict = judge_consensus(question, usable, arguments["judge"] || arguments[:judge],
                                  review_answer: review_answer)
        band = confidence_band(verdict[:score])

        # Honesty: the signal strength reflects the providers that ACTUALLY
        # answered, not the ones requested — if a provider dropped, surviving
        # same-provider answers must NOT be sold as an independent cross-check.
        diverse = usable.map { |r| r[:provider] }.uniq.size >= 2

        # Corroboration mode: a reviewed answer that the panel DISPUTES is an
        # outlier — escalate even when the panel itself agrees (high score).
        recommendation = verdict[:review_aligns] == "disputed" ? "escalate" : band[:action]

        {
          confidence: band[:level],
          score: verdict[:score],
          consensus: verdict[:consensus],
          disagreements: verdict[:disagreements],
          corroboration: verdict[:review_aligns],
          recommendation: recommendation,
          panel_size: usable.size,
          cross_provider: diverse,
          moderator: (if verdict[:judge_provider]
                        { provider: verdict[:judge_provider], model: verdict[:judge_model] }
                      end),
          note: (diverse ? nil : "Surviving responses are from a single provider: agreement has " \
                                  "correlated errors (weak signal)."),
          judge_error: verdict[:judge_error],
          responses: responses,
          budget: CostGuard.status
        }.compact
      end

      # {level:, action:} for a 0-1 score; a non-numeric score -> medium/verify.
      def confidence_band(score)
        return { level: "unknown", action: "verify" } unless score.is_a?(Numeric)

        CONFIDENCE_BANDS.each { |min, level, action| return { level: level, action: action } if score >= min }
        { level: "low", action: "escalate" }
      end

      # Ask a judge model how much the (anonymized) responses agree. Returns
      # {score:, consensus:, disagreements:[]}; a malformed/failed judge yields a
      # neutral verdict (score nil) instead of raising.
      def judge_consensus(question, usable, judge_arg, review_answer: "")
        # Resolve the moderator up front so we can report it (provider + the
        # concrete model, even when the caller let it default).
        jp = (judge_arg && (judge_arg["provider"] || judge_arg[:provider])).to_s
        jp = "openai" if jp.empty?
        jp = MonadicDSL::ProviderConfig.new(jp).standard_key
        jm = (judge_arg && (judge_arg["model"] || judge_arg[:model])).to_s
        jm = default_chat_model_for(jp).to_s if jm.empty?
        judge_id = { judge_provider: jp, judge_model: jm }

        candidates = usable.each_with_index
                           .map { |r, i| "--- Response #{i + 1} ---\n#{r[:text].to_s.strip}" }
                           .join("\n\n")
        # Corroboration mode (anonymized): when an existing answer is under
        # review, also ask whether it aligns with the panel — but never tell the
        # judge which model produced it, so it can't favor a familiar style.
        review_block = review_answer.to_s.strip.empty? ? "" : <<~REVIEW

          Separately, an existing ANSWER UNDER REVIEW was given (source hidden):
          #{review_answer.strip}
          Also judge whether it aligns with the panel's consensus.
        REVIEW
        review_field = review_answer.to_s.strip.empty? ? "" : <<~FIELD.chomp
          ,
           "review_aligns": "<corroborated | partial | disputed — how the answer under review compares to the consensus>"
        FIELD
        prompt = <<~PROMPT
          You are assessing how much a panel of INDEPENDENT AI models AGREE on the answer to a
          question. Agreement is a proxy for trustworthiness: when diverse models independently
          converge the answer is more likely correct; when they diverge it is less reliable. Judge
          the SUBSTANTIVE answer only — ignore wording, length, and style.

          Question:
          #{question}

          Independent responses:
          #{candidates}
          #{review_block}
          Respond with ONLY a JSON object, no prose:
          {"score": <0.0-1.0 how strongly they agree on the substantive answer>,
           "consensus": "<the answer/claim they share, or empty string if none>",
           "disagreements": ["<specific substantive point where they differ>"]#{review_field}}
        PROMPT

        res = execute_query(
          provider: jp, messages: [{ "role" => "user", "content" => prompt }],
          model: jm, max_output: DEFAULT_MAX_OUTPUT, temperature: 0
        )
        # execute_query does NOT raise on budget/transport/model failure — it
        # returns success:false with no text. Surface that as judge_error so the
        # caller can tell "judge couldn't run" from "panel genuinely disagreed".
        if res[:success] == false || res[:text].to_s.strip.empty?
          return judge_id.merge(score: nil, consensus: "", disagreements: [],
                                judge_error: (res[:error] || "judge returned no text"))
        end

        parsed = parse_consensus(res[:text]).merge(judge_id)
        return parsed unless parsed[:score].nil?

        # Successful call but no usable score = unparseable verdict (distinct from
        # a real "no consensus", which the judge would express as a low score).
        parsed.merge(judge_error: "judge response was not a parseable consensus verdict")
      rescue StandardError => e
        judge_id.merge(score: nil, consensus: "", disagreements: [], judge_error: "❌ #{e.class}: #{e.message}")
      end

      # All balanced top-level {...} substrings of `text`, in order. A depth
      # counter (not a greedy regex) so a brace-containing preamble like
      # "comparing {Response 1} ... {\"score\":...}" yields BOTH objects as
      # separate candidates instead of one corrupted span.
      def json_object_candidates(text)
        s = text.to_s.gsub(/```(?:json)?/i, "")
        out = []
        depth = 0
        start = nil
        s.each_char.with_index do |ch, i|
          if ch == "{"
            start = i if depth.zero?
            depth += 1
          elsif ch == "}" && depth.positive?
            depth -= 1
            (out << s[start..i]) if depth.zero?
          end
        end
        out
      end

      # Extract the judge's JSON verdict defensively (it may wrap it in prose or
      # emit example braces first). Picks the first balanced object that parses
      # and carries a "score"; coerces a stringified score and clamps to [0,1].
      def parse_consensus(text)
        data = json_object_candidates(text)
               .filter_map { |c| JSON.parse(c) rescue nil }
               .find { |h| h.is_a?(Hash) && h.key?("score") } || {}
        raw = data["score"]
        score =
          case raw
          when Numeric then raw.to_f
          when String then (Float(raw) rescue nil)
          end
        score = score.clamp(0.0, 1.0) if score
        {
          score: score,
          consensus: data["consensus"].to_s,
          disagreements: (data["disagreements"].is_a?(Array) ? data["disagreements"].map(&:to_s) : []),
          review_aligns: (data["review_aligns"].to_s if data.key?("review_aligns"))
        }
      end

      # ---- Confidence panel selection (graceful-degradation ladder) -------
      #
      # Total over EVERY user configuration: returns the most diverse panel the
      # configured providers allow, and HONESTLY degrades — it never manufactures
      # a strong signal where independence is impossible. Governing rule (from the
      # validation): agreement is meaningful only across INDEPENDENT models; a lone
      # deterministic model "agreeing with itself" is false confidence, so we
      # return :unavailable rather than fake it. The chat-UI verify button reads
      # `signal` to label the result (strong / weak) or disable itself (:none).
      CONFIDENCE_PANEL_CAP = 3
      CONFIDENCE_SELF_CONSISTENCY_K = 3

      def select_confidence_panel(cap: CONFIDENCE_PANEL_CAP)
        usable = usable_chat_providers # distinct providers, one verifier model each

        if usable.size >= 2
          targets = usable.first(cap)
          { mode: :cross_provider, signal: :strong, targets: targets,
            samples: 1, sequential: targets.any? { |t| single_local_server?(t[:provider]) },
            reason: "#{targets.size} distinct providers" }
        elsif usable.size == 1
          t = usable.first
          if sampling_capable?(t[:model])
            { mode: :within_provider, signal: :weak, targets: [t],
              samples: CONFIDENCE_SELF_CONSISTENCY_K, sequential: single_local_server?(t[:provider]),
              reason: "single provider (#{t[:provider]}): self-consistency only — correlated errors, weak signal" }
          else
            { mode: :unavailable, signal: :none, targets: [], samples: 0, sequential: false,
              reason: "only a single deterministic model (#{t[:provider]}/#{t[:model]}) is configured; " \
                      "agreement cannot be measured without independent samples" }
          end
        else
          { mode: :unavailable, signal: :none, targets: [], samples: 0, sequential: false,
            reason: "no chat-capable provider with a resolvable model is configured" }
        end
      end

      # Configured + chat-capable + model-resolvable providers, one verifier model
      # each, in PROVIDER_INFO order (deterministic, diversity-first). The verifier
      # model is the provider's SSOT chat default (a reasonable, cost-controlled
      # pick; never a hardcoded id).
      def usable_chat_providers
        MonadicDSL::ProviderConfig::PROVIDER_INFO.filter_map do |provider, info|
          next unless provider_configured?(info[:api_key])
          next unless provider_host(provider)

          model = default_chat_model_for(provider).to_s
          next if model.empty?

          { provider: provider, model: model }
        end
      rescue StandardError
        []
      end

      def sampling_capable?(model)
        !Monadic::Utils::ModelSpec.rejects_sampling_params?(model)
      rescue StandardError
        true # if capability is unknown, assume samplable (don't over-block)
      end

      # A provider served by a SINGLE local server (one Ollama instance) drops
      # concurrent requests, so its panel/self-consistency calls must run
      # SEQUENTIALLY (gotcha carried over from the ensemble experiment).
      def single_local_server?(provider)
        provider.to_s == "ollama"
      end

      def handle_second_opinion(arguments)
        user_query = (arguments["user_query"] || arguments[:user_query]).to_s
        agent_response = (arguments["agent_response"] || arguments[:agent_response]).to_s
        raise ArgumentError, "user_query is required" if user_query.empty?
        raise ArgumentError, "agent_response is required" if agent_response.empty?

        providers_arg = arguments["providers"] || arguments[:providers]

        if providers_arg.is_a?(Array) && !providers_arg.empty?
          unless providers_arg.size.between?(2, MAX_PARALLEL_PROVIDERS)
            raise ArgumentError,
                  "providers must list 2-#{MAX_PARALLEL_PROVIDERS} provider names"
          end

          targets = providers_arg.each_with_object([]) do |raw, acc|
            canonical = MonadicDSL::ProviderConfig.new(raw.to_s).standard_key
            next if acc.any? { |t| t[:provider] == canonical }
            acc << { provider: canonical }
          end

          second_opinion_host # pre-initialize before spawning threads (avoids a lazy-init race)
          results = run_in_parallel(targets) do |target|
            run_one_second_opinion(
              provider: target[:provider],
              user_query: user_query,
              agent_response: agent_response
            )
          end

          { results: results, budget: CostGuard.status }
        else
          provider = (arguments["provider"] || arguments[:provider]).to_s
          provider = nil if provider.empty?
          provider &&= MonadicDSL::ProviderConfig.new(provider).standard_key

          run_one_second_opinion(
            provider: provider,
            user_query: user_query,
            agent_response: agent_response,
            model: arguments["model"] || arguments[:model]
          ).merge(budget: CostGuard.status)
        end
      end

      # ---- Second-opinion helpers ----------------------------------------

      # Host object that mixes in the SecondOpinionAgent module. The agent
      # builds its own per-provider helper instance internally, so it needs no
      # app instance or session — only CONFIG and the loaded vendor helpers.
      def second_opinion_host
        @second_opinion_host ||= Class.new { include SecondOpinionAgent }.new
      end

      def run_one_second_opinion(provider:, user_query:, agent_response:, model: nil)
        input_tokens = CostGuard.estimate_tokens("#{user_query}\n#{agent_response}")
        begin
          CostGuard.ensure_within!(input_tokens + DEFAULT_MAX_OUTPUT)
        rescue CostGuard::BudgetExceeded => e
          return { provider: provider, success: false, error: "❌ Budget exceeded: #{e.message}" }
        end

        result = second_opinion_host.second_opinion_agent(
          user_query: user_query,
          agent_response: agent_response,
          provider: provider,
          model: model,
          session: {}
        )

        comments = result[:comments] || result["comments"]
        validity = result[:validity] || result["validity"]
        used_model = result[:model] || result["model"]

        CostGuard.record(input_tokens + CostGuard.estimate_tokens(comments))

        {
          provider: provider || used_model.to_s.split(":").first,
          model: used_model,
          success: validity.to_s != "error",
          validity: validity,
          comments: comments
        }
      end

      # ---- Vision (image analysis) ---------------------------------------

      # Rough per-image token allowance for the budget backstop (vision token
      # cost is provider-specific and not returned by the agent).
      IMAGE_TOKENS_ESTIMATE = 1000

      def handle_analyze_image(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        path = (arguments["path"] || arguments[:path]).to_s
        raise ArgumentError, "prompt is required" if prompt.empty?
        raise ArgumentError, "path is required" if path.empty?

        provider = (arguments["provider"] || arguments[:provider]).to_s
        provider = MonadicDSL::ProviderConfig.new(provider).standard_key unless provider.empty?

        input_tokens = CostGuard.estimate_tokens(prompt) + IMAGE_TOKENS_ESTIMATE
        begin
          CostGuard.ensure_within!(input_tokens + DEFAULT_MAX_OUTPUT)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        result = agent_host(ImageAnalysisAgent, provider)
                 .image_analysis_agent(message: prompt, image_path: path)
        success = !error_marker?(result)
        CostGuard.record(input_tokens + CostGuard.estimate_tokens(result))

        {
          provider: (provider.empty? ? "auto" : provider),
          success: success,
          text: (success ? result : nil),
          error: (success ? nil : "❌ #{result}"),
          budget: CostGuard.status
        }.compact
      end

      # ---- Audio transcription (STT) -------------------------------------

      # Rough token allowance for an audio file (STT bills by duration, not
      # tokens, so this is only a budget backstop alongside the transcript).
      AUDIO_TOKENS_ESTIMATE = 2000

      def handle_transcribe_audio(arguments)
        path = (arguments["path"] || arguments[:path]).to_s
        raise ArgumentError, "path is required" if path.empty?

        provider = (arguments["provider"] || arguments[:provider]).to_s
        provider = MonadicDSL::ProviderConfig.new(provider).standard_key unless provider.empty?
        model = (arguments["model"] || arguments[:model])
        language = (arguments["language"] || arguments[:language])

        begin
          CostGuard.ensure_within!(AUDIO_TOKENS_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        result = agent_host(AudioTranscriptionAgent, provider).audio_transcription_agent(
          audio_path: path, model: model, response_format: "text", lang_code: language
        )
        success = !error_marker?(result)
        CostGuard.record(AUDIO_TOKENS_ESTIMATE + CostGuard.estimate_tokens(result))

        {
          provider: (provider.empty? ? "auto" : provider),
          success: success,
          text: (success ? result : nil),
          error: (success ? nil : "❌ #{result}"),
          budget: CostGuard.status
        }.compact
      end

      # ---- Audio analysis (qualitative, Gemini) --------------------------

      AUDIO_ANALYZE_FALLBACK_MODEL = "gemini-3.5-flash"

      def handle_analyze_audio(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        path = (arguments["path"] || arguments[:path]).to_s
        raise ArgumentError, "prompt is required" if prompt.strip.empty?
        raise ArgumentError, "path is required" if path.empty?

        abs_path = resolve_shared_path(path)

        input_tokens = CostGuard.estimate_tokens(prompt) + AUDIO_TOKENS_ESTIMATE
        begin
          CostGuard.ensure_within!(input_tokens + DEFAULT_MAX_OUTPUT)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        # AudioAnalysisAgent is a module_function utility (Gemini direct API,
        # ffmpeg compression) — no host instance needed.
        result = AudioAnalysisAgent.analyze(audio_path: abs_path, prompt: prompt, model: audio_analyze_model)
        success = !error_marker?(result)
        CostGuard.record(input_tokens + CostGuard.estimate_tokens(result))

        {
          provider: "gemini",
          success: success,
          text: (success ? result : nil),
          error: (success ? nil : "❌ #{result}"),
          budget: CostGuard.status
        }.compact
      end

      def audio_analyze_model
        (Monadic::Utils::ModelSpec.default_audio_model("gemini") if defined?(Monadic::Utils::ModelSpec)) ||
          AUDIO_ANALYZE_FALLBACK_MODEL
      rescue StandardError
        AUDIO_ANALYZE_FALLBACK_MODEL
      end

      # ---- Video analysis (frames + vision + audio) ----------------------

      # Frame extraction + multi-frame vision is heavier than a single image.
      VIDEO_ANALYZE_ESTIMATE = 4000

      def handle_analyze_video(arguments)
        path = (arguments["path"] || arguments[:path]).to_s
        raise ArgumentError, "path is required" if path.empty?

        guard = require_background_job("monadic_analyze_video")
        return guard if guard

        query = arguments["query"] || arguments[:query]
        fps = (arguments["fps"] || arguments[:fps]).to_i
        fps = 1 if fps <= 0

        begin
          CostGuard.ensure_within!(VIDEO_ANALYZE_ESTIMATE + DEFAULT_MAX_OUTPUT)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        # The video agent shells out to extract_frames.py in the Python
        # container, then queries a vision provider and transcribes audio — it
        # needs the full MonadicApp surface (send_command + ImageAnalysisAgent +
        # AudioTranscriptionAgent), which MonadicApp already mixes in.
        result = video_analyze_host.analyze_video(file: path, fps: fps, query: query)
        success = !video_error?(result)
        CostGuard.record(VIDEO_ANALYZE_ESTIMATE + CostGuard.estimate_tokens(result))

        {
          success: success,
          text: (success ? result : nil),
          error: (success ? nil : "❌ #{result}"),
          budget: CostGuard.status
        }.compact
      end

      def video_analyze_host
        klass = @hosts_mutex.synchronize do
          @video_analyze_host_class ||= Class.new(MonadicApp) { include VideoAnalyzeAgent }
        end
        klass.new
      end

      # The video agent signals failure with either "ERROR:" or "Error:".
      def video_error?(text)
        text.is_a?(String) && text.start_with?("ERROR:", "Error:", "Video analysis failed:")
      end

      # Resolve a shared-volume path to an absolute path, rejecting traversal.
      # Resolve a path to an absolute path that is guaranteed to live inside the
      # shared volume (~/monadic/data). Relative paths resolve against it;
      # absolute paths are allowed only if they fall within it. This keeps a
      # caller from reading arbitrary host files (the analysis agents read the
      # file directly in the Ruby process and send its bytes to a provider).
      def resolve_shared_path(path)
        raise ArgumentError, "invalid path (traversal not allowed)" if path.match?(%r{(?:\A|/)\.\.(?:/|\z)})

        base = File.expand_path(Monadic::Utils::Environment.shared_volume)
        abs = path.start_with?("/") ? File.expand_path(path) : File.expand_path(File.join(base, path))
        unless abs == base || abs.start_with?("#{base}/")
          raise ArgumentError, "path must be within the shared volume (~/monadic/data)"
        end

        abs
      end

      # ---- Speech synthesis (TTS) ----------------------------------------

      # Supported TTS provider labels (passed verbatim to tts_query.rb, which
      # dispatches on these). Anything else is normalized to the default.
      TTS_PROVIDERS = %w[openai gemini elevenlabs].freeze
      DEFAULT_TTS_VOICES = { "openai" => "alloy", "gemini" => "zephyr" }.freeze

      def handle_speak(arguments)
        text = (arguments["text"] || arguments[:text]).to_s
        raise ArgumentError, "text is required" if text.strip.empty?

        provider = normalize_tts_provider(arguments["provider"] || arguments[:provider])
        voice = (arguments["voice"] || arguments[:voice]).to_s
        voice = DEFAULT_TTS_VOICES[provider].to_s if voice.empty?
        speed = (arguments["speed"] || arguments[:speed] || 1.0)
        language = (arguments["language"] || arguments[:language] || "auto").to_s
        instructions = (arguments["instructions"] || arguments[:instructions]).to_s

        # TTS bills by audio duration, not tokens; the input text length is a
        # reasonable budget backstop alongside the platform's hard ceiling.
        est_tokens = CostGuard.estimate_tokens(text)
        begin
          CostGuard.ensure_within!(est_tokens)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        result = tts_host.text_to_speech(
          provider: provider, text: text, speed: speed,
          voice_id: voice, language: language, instructions: instructions
        ).to_s
        CostGuard.record(est_tokens)

        filename = extract_audio_filename(result)
        success = !filename.nil? && !speak_error?(result)

        {
          provider: provider,
          success: success,
          file: (success ? filename : nil),
          note: (success ? "Saved to ~/monadic/data/#{filename}" : nil),
          error: (success ? nil : "❌ #{result.strip}"),
          budget: CostGuard.status
        }.compact
      end

      # Map a requested provider onto a supported TTS label (default openai).
      def normalize_tts_provider(value)
        v = value.to_s.strip.downcase
        return "openai" if v.empty?
        return "gemini" if %w[gemini google].include?(v)
        return "elevenlabs" if v.start_with?("elevenlabs")
        TTS_PROVIDERS.include?(v) ? v : "openai"
      end

      # The TTS helper reports success as "... saved to <name>.<ext>".
      def extract_audio_filename(output)
        m = output.match(/saved to (\S+\.(?:mp3|wav|ogg|flac|aac))/i)
        m && m[1]
      end

      def speak_error?(output)
        output.start_with?("Error occurred:") ||
          output.include?("An error occurred") ||
          output.include?("ERROR:")
      end

      # Headless TTS host: a bare MonadicApp already mixes in the TTS helper
      # plus send_command/capture_command and resolves the shared-volume path
      # for the current execution mode. Referenced lazily so unit specs (which
      # stub this method) never need the full app loaded.
      def tts_host
        MonadicApp.new
      end

      # ---- Code generation (provider code agents) ------------------------

      # Provider -> code-agent module + entry method. Each agent needs its own
      # provider helper mixed in (api_request / send_query); Provider
      # Independence is preserved per variant (no cross-provider calls).
      CODE_AGENTS = {
        "openai"    => { module: "Monadic::Agents::OpenAICodeAgent", call: :call_openai_code },
        "anthropic" => { module: "Monadic::Agents::ClaudeCodeAgent", call: :call_claude_code },
        "xai"       => { module: "Monadic::Agents::GrokCodeAgent",   call: :call_grok_code }
      }.freeze

      # Auto-selection order when no provider is requested.
      CODE_PROVIDER_ORDER = %w[openai anthropic xai].freeze

      # Code output can be large; reserve a generous backstop on top of the
      # prompt and reconcile with the actual length afterward.
      CODE_OUTPUT_ESTIMATE = 8000

      def handle_generate_code(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        raise ArgumentError, "prompt is required" if prompt.strip.empty?

        guard = require_background_job("monadic_generate_code")
        return guard if guard

        provider = resolve_code_provider(arguments["provider"] || arguments[:provider])
        unless provider
          return { success: false,
                   error: "❌ No code-capable provider is configured (need an API key for " \
                          "openai, anthropic, or xai)." }
        end

        input_tokens = CostGuard.estimate_tokens(prompt)
        begin
          CostGuard.ensure_within!(input_tokens + CODE_OUTPUT_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        spec = CODE_AGENTS[provider]
        reporter = job_progress_reporter
        result = if reporter
                   code_host(provider, spec[:module]).public_send(spec[:call], prompt: prompt, &reporter)
                 else
                   code_host(provider, spec[:module]).public_send(spec[:call], prompt: prompt)
                 end
        result = {} unless result.is_a?(Hash)
        code = result[:code]
        # An agent can report success while leaking a provider error string into
        # the code field (e.g. when api_request rescued mid-pipeline). Treat a
        # "[Provider] ... Error:" code as a failure rather than passing it off.
        success = result[:success] == true && !error_string?(code.to_s)
        CostGuard.record(input_tokens + CostGuard.estimate_tokens(code.to_s))

        {
          provider: provider,
          success: success,
          model: result[:model],
          code: (success ? code : nil),
          error: (success ? nil : "❌ #{result[:error] || code || 'code generation failed'}"),
          budget: CostGuard.status
        }.compact
      end

      # Resolve a requested provider to a configured code provider, or pick the
      # first configured one when none is requested. Returns nil if nothing is
      # available; raises for a named provider that has no code agent.
      def resolve_code_provider(requested)
        req = requested.to_s.strip
        unless req.empty?
          canonical = MonadicDSL::ProviderConfig.new(req).standard_key
          raise ArgumentError, "#{req} has no code agent" unless CODE_AGENTS.key?(canonical)

          return code_provider_configured?(canonical) ? canonical : nil
        end
        CODE_PROVIDER_ORDER.find { |p| code_provider_configured?(p) }
      end

      def code_provider_configured?(provider)
        api_key_env = MonadicDSL::ProviderConfig::PROVIDER_INFO.dig(provider, :api_key)
        provider_configured?(api_key_env)
      end

      # Headless code host: a blank MonadicApp (for the StringUtils / shared
      # infrastructure that the helpers' api_request path needs — e.g.
      # markdown_to_html) with the provider helper and code-agent module mixed
      # in, memoized per provider. Unlike provider_host (send_query only, no app
      # base), the code agents drive the full api_request response pipeline.
      def code_host(provider, module_name)
        helper_name = MonadicDSL::ProviderConfig::PROVIDER_INFO.dig(provider, :helper_module)
        helper = Object.const_get(helper_name)
        agent = Object.const_get(module_name)

        # Memoize the host CLASS (so it is compiled once) but return a FRESH
        # instance per call: agents keep per-call instance state (e.g. access-
        # check memos), and concurrent background jobs must not share one
        # mutable instance.
        klass = @hosts_mutex.synchronize do
          (@code_host_classes ||= {})[provider] ||= Class.new(MonadicApp) do
            include helper
            include agent
          end
        end
        klass.new
      end

      # ---- Media generation (image) --------------------------------------

      # Internal provider labels (match the helper method names). Requested
      # aliases (xai/google) are normalized onto these.
      IMAGE_PROVIDERS = %w[openai grok gemini].freeze

      # Media generation bills per image / per second / per request — not per
      # token — so these flat reservations are token-equivalent *cost proxies*,
      # not real token counts. They are scaled to the rough dollar cost of each
      # operation relative to text tokens, so the budget meaningfully limits the
      # most expensive operations (a token-cheap estimate would let a runaway
      # client generate hundreds of videos before the ceiling bites).
      IMAGE_GEN_ESTIMATE = 4000

      def handle_generate_image(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        raise ArgumentError, "prompt is required" if prompt.strip.empty?

        guard = require_background_job("monadic_generate_image")
        return guard if guard

        provider = normalize_image_provider(arguments["provider"] || arguments[:provider])
        aspect_ratio = arguments["aspect_ratio"] || arguments[:aspect_ratio]
        size = arguments["size"] || arguments[:size]

        begin
          CostGuard.ensure_within!(IMAGE_GEN_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        # The helper methods wrap themselves in ProgressBroadcaster.with_progress,
        # which mirrors progress into the current job for polling clients.
        raw = invoke_image_generator(provider, prompt: prompt, aspect_ratio: aspect_ratio, size: size)
        result = normalize_image_result(provider, raw)
        CostGuard.record(IMAGE_GEN_ESTIMATE)

        {
          provider: provider,
          success: result[:success],
          files: (result[:success] ? result[:files] : nil),
          note: (result[:success] ? "Saved to ~/monadic/data/" : nil),
          error: (result[:success] ? nil : "❌ #{result[:error]}"),
          budget: CostGuard.status
        }.compact
      end

      def normalize_image_provider(value)
        v = value.to_s.strip.downcase
        return "openai" if v.empty?
        return "gemini" if %w[gemini google].include?(v)
        return "grok" if %w[grok xai].include?(v)

        IMAGE_PROVIDERS.include?(v) ? v : "openai"
      end

      def invoke_image_generator(provider, prompt:, aspect_ratio:, size:)
        case provider
        when "openai"
          model = Monadic::Utils::ModelSpec.default_image_model("openai") || "gpt-image-2"
          media_app_host.generate_image_with_openai(
            operation: "generate", model: model, prompt: prompt, size: (size || "1024x1024"), n: 1
          )
        when "grok"
          media_app_host.generate_image_with_grok(
            prompt: prompt, aspect_ratio: aspect_ratio, operation: "generate"
          )
        when "gemini"
          gemini_media_host.generate_image_with_gemini(
            prompt: prompt, operation: "generate", model: "gemini",
            aspect_ratio: aspect_ratio, image_size: size
          )
        end
      end

      # OpenAI/Grok image helpers shell out via send_command, so they need a
      # full MonadicApp host (like tts_host).
      def media_app_host
        MonadicApp.new
      end

      # Gemini media host. Unlike query (send_query only), some Gemini media
      # methods shell out via send_command (e.g. Veo video → video_generator
      # script), so this needs the MonadicApp base, not a bare helper host. The
      # class is memoized; a fresh instance is returned per call so concurrent
      # jobs never share one mutable host.
      def gemini_media_host
        klass = @hosts_mutex.synchronize do
          @gemini_media_host_class ||= Class.new(MonadicApp) { include GeminiHelper }
        end
        klass.new
      end

      # Normalize an image result to {success:, files:|error:}. OpenAI prints
      # "Saved file: <path>" lines; every other generator returns JSON.
      def normalize_image_result(provider, raw)
        return normalize_media_json(raw) unless provider == "openai"

        text = raw.to_s
        files = text.scan(/Saved file:\s*(\S+)/i).flatten.map { |p| File.basename(p) }
        return { success: true, files: files } if files.any? && !text.start_with?("Error occurred:")

        { success: false, error: text }
      end

      # Shared normalizer for the JSON-returning generators (grok image/video,
      # Lyria music, Veo video). Some return clean JSON; Veo returns the raw
      # send_command text with a JSON object embedded on its own line (and a
      # decoy Ruby-hash "{...}" earlier in the log). Filenames may be top-level
      # or nested under a videos/images array.
      def normalize_media_json(raw)
        data = parse_embedded_json(raw)
        if data && data["success"] == true
          files = media_filenames(data)
          return { success: true, files: files } if files.any?
        end
        { success: false, error: (data && (data["message"] || data["error"])) || raw.to_s }
      end

      # Parse a JSON object that may be embedded in surrounding log text. Tries
      # the whole string first, then the last line that is a JSON object (so a
      # "Using parameters: {..=>..}" Ruby-hash decoy is skipped).
      def parse_embedded_json(raw)
        str = raw.to_s
        whole = try_parse_json_object(str)
        return whole if whole

        str.each_line.reverse_each do |line|
          line = line.strip
          next unless line.start_with?("{") && line.end_with?("}")

          parsed = try_parse_json_object(line)
          return parsed if parsed
        end
        nil
      end

      def try_parse_json_object(str)
        data = JSON.parse(str)
        data.is_a?(Hash) ? data : nil
      rescue JSON::ParserError
        nil
      end

      # Collect saved filenames from a generator result: top-level filename/file
      # plus any videos/images/files array of {filename}/{file} or bare strings.
      def media_filenames(data)
        files = [data["filename"], data["file"]]
        %w[videos images files].each do |key|
          arr = data[key]
          next unless arr.is_a?(Array)

          arr.each { |e| files << (e.is_a?(Hash) ? (e["filename"] || e["file"]) : e) }
        end
        files.compact.uniq
      end

      # ---- Media generation (video) --------------------------------------

      VIDEO_PROVIDERS = %w[gemini grok].freeze
      # Cost proxy (see IMAGE_GEN_ESTIMATE): video is by far the most expensive
      # operation, so it reserves the largest share of the budget.
      VIDEO_GEN_ESTIMATE = 50_000

      def handle_generate_video(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        raise ArgumentError, "prompt is required" if prompt.strip.empty?

        guard = require_background_job("monadic_generate_video")
        return guard if guard

        provider = normalize_video_provider(arguments["provider"] || arguments[:provider])
        aspect_ratio = arguments["aspect_ratio"] || arguments[:aspect_ratio]
        duration = arguments["duration"] || arguments[:duration]
        image_path = arguments["image_path"] || arguments[:image_path]

        begin
          CostGuard.ensure_within!(VIDEO_GEN_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        raw = invoke_video_generator(provider, prompt: prompt, aspect_ratio: aspect_ratio,
                                               duration: duration, image_path: image_path)
        result = normalize_media_json(raw)
        CostGuard.record(VIDEO_GEN_ESTIMATE)

        {
          provider: provider,
          success: result[:success],
          files: (result[:success] ? result[:files] : nil),
          note: (result[:success] ? "Saved to ~/monadic/data/" : nil),
          error: (result[:success] ? nil : "❌ #{result[:error]}"),
          budget: CostGuard.status
        }.compact
      end

      def normalize_video_provider(value)
        v = value.to_s.strip.downcase
        return "gemini" if v.empty?
        return "grok" if %w[grok xai].include?(v)
        return "gemini" if %w[gemini google veo].include?(v)

        VIDEO_PROVIDERS.include?(v) ? v : "gemini"
      end

      def invoke_video_generator(provider, prompt:, aspect_ratio:, duration:, image_path:)
        case provider
        when "gemini"
          args = { prompt: prompt }
          args[:aspect_ratio] = aspect_ratio if aspect_ratio
          args[:image_path] = image_path if image_path
          args[:duration_seconds] = duration.to_i if duration
          gemini_media_host.generate_video_with_veo(**args)
        when "grok"
          args = { prompt: prompt }
          args[:aspect_ratio] = aspect_ratio if aspect_ratio
          args[:duration] = duration.to_i if duration
          args[:image_path] = image_path if image_path
          media_app_host.generate_video_with_grok_imagine(**args)
        end
      end

      # ---- Media generation (music) --------------------------------------

      # Cost proxy (see IMAGE_GEN_ESTIMATE).
      MUSIC_GEN_ESTIMATE = 6000

      def handle_generate_music(arguments)
        prompt = (arguments["prompt"] || arguments[:prompt]).to_s
        raise ArgumentError, "prompt is required" if prompt.strip.empty?

        guard = require_background_job("monadic_generate_music")
        return guard if guard

        output_format = arguments["format"] || arguments[:format]

        begin
          CostGuard.ensure_within!(MUSIC_GEN_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        args = { prompt: prompt }
        args[:output_format] = output_format if output_format
        raw = gemini_media_host.generate_music_with_lyria(**args)
        result = normalize_media_json(raw)
        CostGuard.record(MUSIC_GEN_ESTIMATE)

        {
          provider: "gemini",
          success: result[:success],
          files: (result[:success] ? result[:files] : nil),
          note: (result[:success] ? "Saved to ~/monadic/data/" : nil),
          error: (result[:success] ? nil : "❌ #{result[:error]}"),
          budget: CostGuard.status
        }.compact
      end

      # ---- Autonomous tool-using agent -----------------------------------

      # Generous flat budget reservation: the agent runs a multi-call tool loop
      # (api_request) that does NOT pass through CostGuard per call, so this gates
      # whether the agent may START. The hard per-run bound is the engine's
      # MAX_FUNC_CALLS (20 tool calls/turn) + stuck-loop detection.
      AGENT_ESTIMATE = 60_000

      def handle_agent(arguments)
        task = (arguments["task"] || arguments[:task]).to_s
        raise ArgumentError, "task is required" if task.strip.empty?

        guard = require_background_job("monadic_agent")
        return guard if guard

        provider = (arguments["provider"] || arguments[:provider]).to_s
        provider = provider.empty? ? "openai" : MonadicDSL::ProviderConfig.new(provider).standard_key
        groups = arguments["tools"] || arguments[:tools] || ConduitAgent::DEFAULT_GROUPS

        begin
          CostGuard.ensure_within!(AGENT_ESTIMATE)
        rescue CostGuard::BudgetExceeded => e
          return { success: false, error: "❌ Budget exceeded: #{e.message}", budget: CostGuard.status }
        end

        model = default_chat_model_for(provider)
        result = ConduitAgent.run(task: task, provider: provider, model: model, groups: groups).to_s
        success = !result.start_with?("ERROR:") && !error_string?(result) && !result.strip.empty?
        CostGuard.record(AGENT_ESTIMATE + CostGuard.estimate_tokens(result))

        {
          provider: provider,
          model: model,
          tools: Array(groups),
          success: success,
          text: (success ? result : nil),
          error: (success ? nil : "❌ #{result}"),
          budget: CostGuard.status
        }.compact
      end

      # ---- Background jobs (async submit / poll / cancel) ----------------

      # Job-control tools cannot themselves be submitted as jobs (no recursion).
      ASYNC_INELIGIBLE = %w[monadic_submit monadic_poll monadic_cancel monadic_jobs].freeze

      # Long-running tools that must run as a background job. Calling one
      # synchronously would occupy the single Falcon reactor for seconds-to-
      # minutes and freeze the Web UI, so a direct call is refused with guidance
      # to submit it instead. Returns an error hash when called directly (no job
      # on this thread), or nil to proceed (running inside monadic_submit's job).
      ASYNC_REQUIRED = %w[
        monadic_generate_image monadic_generate_video monadic_generate_music
        monadic_generate_code monadic_analyze_video monadic_agent
      ].freeze

      def require_background_job(tool_name)
        return nil unless JobStore.current_job_id.nil?

        {
          success: false,
          error: "❌ #{tool_name} is long-running and must run in the background. " \
                 "Call monadic_submit with tool=\"#{tool_name}\" (and the same arguments), " \
                 "then poll with monadic_poll."
        }
      end

      def handle_submit(arguments)
        tool = (arguments["tool"] || arguments[:tool]).to_s
        raise ArgumentError, "tool is required" if tool.empty?
        raise ArgumentError, "unknown tool: #{tool}" unless tool?(tool)
        raise ArgumentError, "#{tool} cannot be run as a background job" if ASYNC_INELIGIBLE.include?(tool)

        job_args = arguments["arguments"] || arguments[:arguments] || {}
        raise ArgumentError, "arguments must be an object" unless job_args.is_a?(Hash)

        begin
          # The block runs on the job's own thread (off the Falcon reactor),
          # re-entering Conduit dispatch for the target tool. CostGuard inside
          # that tool still enforces the budget ceiling at run time.
          job = JobStore.submit(tool: tool, arguments: job_args) { call(tool, job_args) }
        rescue JobStore::ConcurrencyLimit => e
          return { success: false, error: "❌ #{e.message}" }
        end

        { success: true, job_id: job.id, tool: tool, status: job.status }
      end

      def handle_poll(arguments)
        id = (arguments["job_id"] || arguments[:job_id]).to_s
        raise ArgumentError, "job_id is required" if id.empty?

        job = JobStore.fetch(id)
        return { success: false, error: "❌ Unknown or expired job: #{id}" } unless job

        job_view(job)
      end

      def handle_cancel(arguments)
        id = (arguments["job_id"] || arguments[:job_id]).to_s
        raise ArgumentError, "job_id is required" if id.empty?

        job = JobStore.cancel(id)
        return { success: false, error: "❌ Unknown or expired job: #{id}" } unless job

        job_view(job)
      end

      def handle_jobs(_arguments)
        { jobs: JobStore.list }
      end

      # Build a progress callback bound to the current background job, or nil
      # when running synchronously (no job). Agents fire their progress block
      # from sub-threads, so the job id is captured in the closure here — read
      # once on the job thread — rather than via a thread-local.
      def job_progress_reporter
        job_id = JobStore.current_job_id
        return nil unless job_id

        ->(fragment) { JobStore.report(job_id, progress_message(fragment)) }
      end

      # Reduce an agent/generator progress fragment to a short human snapshot.
      def progress_message(fragment)
        return fragment.to_s unless fragment.is_a?(Hash)

        content = fragment["content"] || fragment[:content]
        step = fragment["step_progress"] || fragment[:step_progress]
        if step
          current = (step["current"] || step[:current]).to_i
          total = step["total"] || step[:total]
          "#{content} (#{current + 1}/#{total})"
        else
          content.to_s
        end
      end

      # Full view of a single job, including the tool's result/error when done.
      def job_view(job)
        {
          job_id: job.id,
          tool: job.tool,
          status: job.status,
          progress: job.progress,
          progress_at: job.progress_at&.iso8601,
          result: job.result,
          error: job.error,
          created_at: job.created_at&.iso8601,
          finished_at: job.finished_at&.iso8601
        }.compact
      end

      # ---- Analysis-agent helpers ----------------------------------------

      # Build a headless host mixing in an analysis agent module. These agents
      # read settings["provider"] to prefer a provider, so we supply a minimal
      # settings carrying the (optional) requested provider; an empty value
      # triggers each agent's own first-available fallback.
      def agent_host(agent_module, provider)
        klass = Class.new do
          attr_accessor :_conduit_provider
          def settings
            { "provider" => _conduit_provider.to_s }
          end
        end
        klass.include(agent_module)
        host = klass.new
        host._conduit_provider = provider
        host
      end

      # The analysis agents signal failure with a leading "ERROR:" string.
      def error_marker?(text)
        text.is_a?(String) && text.start_with?("ERROR:")
      end

      # ---- Knowledge Base (local PDF KB via Monadic::Pdf::Store) ----------

      DEFAULT_KB = "global"
      KB_MAX_TOP_N = 50

      def handle_search_kb(arguments)
        query = (arguments["query"] || arguments[:query]).to_s
        raise ArgumentError, "query is required" if query.empty?

        kb = kb_namespace(arguments)
        top_n = (arguments["top_n"] || arguments[:top_n]).to_i
        top_n = 5 if top_n <= 0
        top_n = KB_MAX_TOP_N if top_n > KB_MAX_TOP_N
        level = (arguments["level"] || arguments[:level]).to_s
        level = "item" unless %w[item doc].include?(level)

        store = kb_store(kb)
        hits = level == "doc" ? store.find_closest_doc(query, top_n: top_n)
                              : store.find_closest_text(query, top_n: top_n)

        { knowledge_base: kb, level: level, count: hits.size, results: hits }
      rescue Monadic::VectorStore::BackendError => e
        { knowledge_base: kb, success: false,
          error: "❌ Knowledge Base unavailable: #{e.message} (is qdrant/embeddings running?)" }
      end

      def handle_list_kb(arguments)
        kb = kb_namespace(arguments)
        store = kb_store(kb)
        documents = store.list_titles
        { knowledge_base: kb, count: documents.size, documents: documents }
      rescue Monadic::VectorStore::BackendError => e
        { knowledge_base: kb, success: false,
          error: "❌ Knowledge Base unavailable: #{e.message} (is qdrant/embeddings running?)" }
      end

      def handle_import_kb(arguments)
        title = (arguments["title"] || arguments[:title]).to_s
        raise ArgumentError, "title is required" if title.empty?

        kb = kb_namespace(arguments)
        text = (arguments["text"] || arguments[:text]).to_s
        path = (arguments["path"] || arguments[:path]).to_s

        chunks, source =
          if !text.empty?
            [chunk_text(text), "text"]
          elsif !path.empty?
            [extract_pdf_chunks(path), path]
          else
            raise ArgumentError, "provide either `text` or `path`"
          end

        raise "no text could be extracted to import" if chunks.empty?

        store = kb_store(kb)
        doc_data = { title: title, items: chunks.size, metadata: { source: source } }
        items_data = chunks.map do |c|
          { text: (c["text"] || c[:text]), metadata: { tokens: (c["tokens"] || c[:tokens]) } }
        end
        doc_id = store.store_embeddings(doc_data, items_data)

        { knowledge_base: kb, doc_id: doc_id, title: title, chunks: chunks.size, source: source }
      rescue Monadic::VectorStore::BackendError => e
        { knowledge_base: kb, success: false,
          error: "❌ Knowledge Base unavailable: #{e.message} (is qdrant/embeddings running?)" }
      end

      # ---- Knowledge Base helpers ----------------------------------------

      def kb_namespace(arguments)
        ns = (arguments["knowledge_base"] || arguments[:knowledge_base]).to_s.strip
        ns.empty? ? DEFAULT_KB : ns
      end

      def kb_store(knowledge_base)
        require_relative '../pdf'
        Monadic::Pdf::Store.new(app_key: knowledge_base)
      end

      # Token-based line chunker mirroring PDF2Text#split_text, but for arbitrary
      # text (no PDF / python container needed).
      def chunk_text(text, max_tokens: kb_chunk_tokens, overlap_lines: kb_overlap_lines, separator: "\n")
        return chunk_text_by_length(text) unless tokenizer_available?

        tok = MonadicApp::TOKENIZER
        lines = text.split(separator)
        chunks = []
        current = []
        current_tokens = 0

        lines.each do |line|
          line_token_count = tok.get_tokens_sequence(line).size
          if current_tokens + line_token_count > max_tokens && !current.empty?
            chunks << { "text" => current.join(separator).strip, "tokens" => current_tokens }
            current = current.last(overlap_lines)
            current_tokens = tok.get_tokens_sequence(current.join(separator)).size
          end
          current << line.strip
          current_tokens += line_token_count
        end
        chunks << { "text" => current.join(separator).strip, "tokens" => current_tokens } unless current.empty?
        chunks.reject { |c| c["text"].to_s.empty? }
      end

      # Fallback chunker when the tokenizer is unavailable: split on ~max_chars.
      def chunk_text_by_length(text, max_chars: 8000)
        text.scan(/.{1,#{max_chars}}/m).map { |slice| { "text" => slice.strip, "tokens" => nil } }
            .reject { |c| c["text"].empty? }
      end

      def extract_pdf_chunks(path)
        unless path.downcase.end_with?(".pdf")
          raise ArgumentError, "path must point to a .pdf file"
        end
        raise ArgumentError, "file not found: #{path}" unless File.exist?(path)

        require_relative '../utils/pdf_text_extractor'
        pdf = PDF2Text.new(path: path, max_tokens: kb_chunk_tokens, separator: "\n",
                           overwrap_lines: kb_overlap_lines)
        pdf.extract
        pdf.split_text
      end

      def kb_chunk_tokens
        defined?(RAG_TOKENS) ? RAG_TOKENS : 4000
      end

      def kb_overlap_lines
        defined?(RAG_OVERLAP_LINES) ? RAG_OVERLAP_LINES : 4
      end

      def tokenizer_available?
        defined?(MonadicApp) && defined?(MonadicApp::TOKENIZER) && MonadicApp::TOKENIZER
      end

      # ---- Query helpers --------------------------------------------------

      # Shared single-provider execution used by both monadic_query and the
      # parallel fan-out. Builds a headless per-provider host (Provider
      # Independence), optionally grounds the query in a local KB and/or masks
      # PII (the Conduit differentiators), gates spend through CostGuard, and
      # returns a normalized result hash.
      # True when a model can spend hidden reasoning/thinking tokens that do not
      # appear in the visible response text (responses-API reasoning, extended
      # thinking, or adaptive reasoning). Used to charge the budget conservatively
      # since send_query exposes no provider usage. Signals are fragmented across
      # providers, so we OR the available capability accessors; a false negative
      # only reverts to the visible-text estimate (no worse than before).
      def hidden_reasoning_capable?(model)
        ms = Monadic::Utils::ModelSpec
        ms.responses_api?(model) || ms.supports_thinking?(model) || ms.adaptive_reasoning?(model)
      rescue StandardError
        false
      end

      def execute_query(provider:, messages:, system: "", model: nil,
                        max_output: nil, temperature: nil,
                        knowledge_base: nil, privacy: nil)
        model = model.to_s.strip
        model = nil if model.empty?
        model ||= default_chat_model_for(provider)
        raise "no chat model resolved for provider '#{provider}'" if model.to_s.empty?

        max_output = max_output.to_i
        max_output = DEFAULT_MAX_OUTPUT if max_output <= 0

        host = provider_host(provider)
        unless host
          raise "no vendor helper available for provider '#{provider}' " \
                "(unknown provider or helper not loaded)"
        end

        # (1) KB grounding — retrieve relevant context for the latest user turn.
        grounded = false
        kb_context = ""
        kb = knowledge_base.to_s.strip
        unless kb.empty?
          begin
            kb_context, grounded = retrieve_kb_context(messages, kb)
          rescue Monadic::VectorStore::BackendError => e
            return { provider: provider, model: model, success: false,
                     error: "❌ Knowledge Base unavailable: #{e.message} (grounding requested)" }
          end
        end

        # Fold the explicit system prompt and any KB context into the user turn.
        # send_query does NOT uniformly honor a top-level system across providers
        # (OpenAI-family read a system-role message; Claude rejects one and reads
        # options["system"]). Folding into the user message is the one delivery
        # that works for every provider without provider-specific branching.
        preamble = [system.to_s, kb_context].reject { |s| s.to_s.empty? }.join("\n\n")
        send_messages = apply_preamble(messages, preamble)

        # (2) Privacy masking — mask PII before sending; restore after.
        pipeline = privacy_enabled?(privacy) ? build_privacy_pipeline(privacy) : nil
        if pipeline
          begin
            send_messages = send_messages.map do |m|
              { "role" => m["role"], "content" => mask_text(pipeline, m["content"], m["role"]) }
            end
          rescue Monadic::Utils::Privacy::BackendError => e
            return { provider: provider, model: model, success: false,
                     error: "❌ Privacy masking unavailable: #{e.message} (refusing to send unmasked)" }
          end
        end

        input_tokens = CostGuard.estimate_tokens(send_messages.map { |m| m["content"] }.join("\n"))

        begin
          CostGuard.ensure_within!(input_tokens + max_output)
        rescue CostGuard::BudgetExceeded => e
          return { provider: provider, model: model, success: false,
                   error: "❌ Budget exceeded: #{e.message}" }
        end

        body = { "messages" => send_messages, "model" => model, "max_tokens" => max_output }
        body["temperature"] = temperature unless temperature.nil?

        raw = host.send_query(body, model: model)
        normalized = normalize_query_response(raw)

        # Restore masked placeholders in the response back to original values.
        if pipeline && normalized[:text]
          normalized = normalized.merge(text: pipeline.after_receive_from_llm(normalized[:text]).text)
        end

        # Reasoning/thinking models spend hidden tokens (billed at the output rate)
        # that never appear in the visible response text. Estimating output from
        # that text alone undercounts real spend by up to an order of magnitude,
        # softening the budget ceiling exactly for the most expensive models.
        # send_query returns text only (no provider usage), so we fail closed:
        # charge such models the output we already reserved in ensure_within!.
        # This over-counts short replies — the safe direction for a spend *ceiling*
        # (a safety backstop, not an accounting ledger).
        output_tokens = CostGuard.estimate_tokens(normalized[:text] || normalized[:error])
        output_tokens = max_output if hidden_reasoning_capable?(model) && max_output > output_tokens
        CostGuard.record(input_tokens + output_tokens)

        {
          provider: provider,
          model: model,
          success: normalized[:success],
          text: normalized[:text],
          tool_calls: normalized[:tool_calls],
          error: normalized[:error],
          grounded: (grounded || nil),
          privacy: (pipeline ? true : nil),
          # Best-effort hint: the text looks cut off (no sentence-final
          # punctuation), e.g. a reasoning model that spent `max_tokens` on
          # internal reasoning before finishing. Raise `max_tokens` and retry.
          possibly_incomplete: (true if normalized[:success] && looks_incomplete?(normalized[:text])),
          usage: {
            input_tokens_est: input_tokens,
            output_tokens_est: output_tokens,
            note: "estimated via tiktoken; send_query does not expose provider usage"
          }
        }.compact
      end

      # ---- KB grounding + Privacy helpers --------------------------------

      KB_GROUNDING_TOP_N = 4

      # PII-focused default mask set (excludes LOCATION/DATE_TIME by design).
      DEFAULT_PRIVACY_MASK_TYPES = %i[person email phone credit_card ip iban us_ssn].freeze

      # Search the KB with the latest user turn. Returns [context_block, grounded?].
      def retrieve_kb_context(messages, knowledge_base)
        user_text = messages.reverse.find { |m| m["role"].to_s == "user" }&.dig("content").to_s
        return ["", false] if user_text.empty?

        hits = kb_store(knowledge_base).find_closest_text(user_text, top_n: KB_GROUNDING_TOP_N)
        context = hits.map { |h| (h[:text] || h["text"]).to_s }.reject(&:empty?).join("\n\n")
        return ["", false] if context.empty?

        ["Relevant context from the knowledge base (use it if helpful):\n#{context}", true]
      end

      # Fold a preamble (system instructions + KB context) into the latest user
      # message so it reaches every provider uniformly (see execute_query note).
      def apply_preamble(messages, preamble)
        return messages if preamble.to_s.empty?

        idx = messages.rindex { |m| m["role"].to_s == "user" }
        if idx
          messages.each_with_index.map do |m, i|
            i == idx ? { "role" => m["role"], "content" => "#{preamble}\n\n#{m["content"]}" } : m
          end
        else
          [{ "role" => "user", "content" => preamble }] + messages
        end
      end

      def privacy_enabled?(privacy)
        case privacy
        when true then true
        when Hash then privacy["enabled"] != false && privacy[:enabled] != false
        else false
        end
      end

      def build_privacy_pipeline(privacy)
        require_relative '../utils/privacy/pipeline'
        opts = privacy.is_a?(Hash) ? privacy : {}
        mask_types = Array(opts["mask_types"] || opts[:mask_types]).map(&:to_sym)
        mask_types = DEFAULT_PRIVACY_MASK_TYPES if mask_types.empty?
        language = (opts["language"] || opts[:language] || "en").to_s

        Monadic::Utils::Privacy::Pipeline.new(
          backend: Monadic::Utils::Privacy::PresidioBackend.new,
          config: {
            enabled: true,
            mask_types: mask_types,
            score_threshold: 0.4,
            honorific_trim: true,
            on_failure: :block
          },
          session: { parameters: { conversation_language: language }, monadic_state: {} }
        )
      end

      def mask_text(pipeline, text, role)
        return text.to_s if text.to_s.empty?
        raw = Monadic::Utils::Privacy::RawMessage.new(text.to_s, role.to_s, {})
        pipeline.before_send_to_llm(raw).text
      end

      # Run a block per target concurrently, bounded by PARALLEL_TIMEOUT of
      # total wall time. A target that raises or times out yields a structured
      # failure rather than aborting the whole fan-out.
      def run_in_parallel(targets)
        started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        threads = targets.map do |target|
          [target, Thread.new do
            begin
              yield(target)
            rescue StandardError => e
              { provider: target[:provider], model: target[:model],
                success: false, error: "❌ #{e.class}: #{e.message}" }
            end
          end]
        end

        threads.map do |target, thread|
          elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started
          remaining = [PARALLEL_TIMEOUT - elapsed, 0.1].max
          if thread.join(remaining)
            thread.value
          else
            thread.kill
            {
              provider: target[:provider],
              model: target[:model],
              success: false,
              error: "❌ timed out after #{PARALLEL_TIMEOUT}s"
            }
          end
        end
      end

      # Accept either a single `message` string or a `messages` array of
      # role/content (or role/text) turns; return Chat-Completions style
      # string-keyed message hashes.
      def normalize_messages(arguments)
        raw_messages = arguments["messages"] || arguments[:messages]
        single = arguments["message"] || arguments[:message]

        if raw_messages.is_a?(Array) && !raw_messages.empty?
          raw_messages.map do |m|
            next nil unless m.is_a?(Hash)
            role = (m["role"] || m[:role]).to_s
            role = "user" if role.empty?
            content = (m["content"] || m[:content] || m["text"] || m[:text]).to_s
            next nil if content.empty?
            { "role" => role, "content" => content }
          end.compact
        elsif !single.to_s.empty?
          [{ "role" => "user", "content" => single.to_s }]
        else
          []
        end
      end

      def default_chat_model_for(provider)
        model = Monadic::Utils::ModelSpec.default_chat_model(provider)
        return model if model && !model.to_s.empty?

        if defined?(::SystemDefaults)
          ::SystemDefaults.get_default_model(provider)
        end
      rescue StandardError
        nil
      end

      # Build (and memoize) a dedicated headless host for a provider: a bare
      # object that mixes in only that provider's vendor helper, so it responds
      # to send_query. We deliberately CONSTRUCT this host rather than borrow a
      # Chat app from APPS — send_query is stateless w.r.t. app prompt/context
      # (it reads only its options + CONFIG), so a headless host carries no
      # stray system prompt and needs no app to exist. The helper module is
      # resolved from the SSOT (PROVIDER_INFO). This mirrors what
      # SecondOpinionAgent#get_provider_helper does internally, keeping a single
      # principle across Conduit: the platform owns its own provider hosts.
      def provider_host(provider)
        helper_name = MonadicDSL::ProviderConfig::PROVIDER_INFO.dig(provider, :helper_module)
        return nil unless helper_name && Object.const_defined?(helper_name)

        klass = @hosts_mutex.synchronize do
          @provider_host_classes[provider] ||= begin
            helper = Object.const_get(helper_name)
            Class.new.tap { |k| k.include(helper) }
          end
        end
        klass.new
      end

      # send_query returns a String (text, or a formatted "[Provider] X Error:"
      # string) or a Hash { text:, tool_calls: }. Normalize to a uniform shape.
      def normalize_query_response(raw)
        case raw
        when String
          if error_string?(raw)
            { success: false, error: raw }
          else
            { success: true, text: raw }
          end
        when Hash
          text = raw[:text] || raw["text"]
          tool_calls = raw[:tool_calls] || raw["tool_calls"]
          if text && !text.to_s.empty?
            { success: true, text: text, tool_calls: (tool_calls unless tool_calls.to_s.empty?) }
          else
            { success: false, error: raw.to_s }
          end
        when nil
          { success: false, error: "empty response from provider" }
        else
          { success: true, text: raw.to_s }
        end
      end

      # Detects ErrorFormatter's "[Provider] <Category> Error: ..." convention.
      def error_string?(text)
        text.is_a?(String) && text.match?(/\A\[[^\]]+\][^\n]*?Error:/)
      end

      # Heuristic: a non-empty answer that does not end on sentence-final
      # punctuation (incl. CJK and closing quotes/brackets) likely got cut off.
      # Used only as a soft hint — some valid answers legitimately end this way.
      def looks_incomplete?(text)
        s = text.to_s.strip
        return false if s.empty?

        !s.match?(/[.!?…。！？”’"')\]\}]\z/)
      end

      # ---- Status helpers -------------------------------------------------

      def execution_mode
        if defined?(Monadic::Utils::Environment) &&
           Monadic::Utils::Environment.respond_to?(:in_container?)
          Monadic::Utils::Environment.in_container? ? "container" : "host"
        else
          "unknown"
        end
      end

      def safe_mcp_status
        return {} unless defined?(Monadic::MCP::Server) &&
                         Monadic::MCP::Server.respond_to?(:status)

        Monadic::MCP::Server.status
      rescue StandardError
        {}
      end

      def provider_readiness
        MonadicDSL::ProviderConfig::PROVIDER_INFO.map do |provider, info|
          {
            provider: provider,
            display_group: info[:display_group],
            configured: provider_configured?(info[:api_key])
          }
        end
      end

      # A provider with no api_key requirement (Ollama, local) is considered
      # configured; otherwise the key must be present and non-empty in CONFIG.
      def provider_configured?(api_key_env)
        return true if api_key_env.nil?
        return false unless defined?(CONFIG) && CONFIG

        !CONFIG[api_key_env].to_s.strip.empty?
      end

      def container_readiness
        return [] unless defined?(Monadic::Utils::ContainerDependencies)

        deps = Monadic::Utils::ContainerDependencies
        deps::CONTAINER_NAMES.map do |service, container_name|
          running =
            begin
              deps.container_running?(service)
            rescue StandardError
              nil
            end
          {
            service: service.to_s,
            container: container_name,
            running: running
          }
        end
      end

      # ---- Model listing helpers -----------------------------------------

      # Text-LLM categories whose models get capability enrichment. Media
      # categories (image/video/tts/music/audio_transcription) are listed under
      # `categories` for discovery but not enriched with chat capabilities.
      TEXT_CATEGORIES = %w[chat code vision].freeze

      def provider_models_entry(provider, include_deprecated)
        info = MonadicDSL::ProviderConfig::PROVIDER_INFO[provider]
        categories = provider_categories(provider)

        text_models = TEXT_CATEGORIES
                      .flat_map { |cat| categories[cat] || [] }
                      .uniq

        models = text_models.map { |id| model_capabilities(id) }
        models = models.reject { |m| m[:deprecated] } unless include_deprecated

        {
          provider: provider,
          display_group: info && info[:display_group],
          configured: provider_configured?(info && info[:api_key]),
          default_chat_model: categories.dig("chat", 0),
          categories: categories,
          models: models
        }
      end

      def provider_categories(provider)
        defaults = Monadic::Utils::ModelSpec.load_provider_defaults
        entry = defaults[provider]
        entry.is_a?(Hash) ? entry : {}
      rescue StandardError
        {}
      end

      def model_capabilities(model_id)
        spec = Monadic::Utils::ModelSpec.get_model_spec(model_id)
        if spec.nil? || spec.empty?
          return { id: model_id, known: false }
        end

        {
          id: model_id,
          known: true,
          context_window: numeric_max(spec["context_window"]),
          max_output_tokens: numeric_max(spec["max_output_tokens"]),
          vision: Monadic::Utils::ModelSpec.vision_capability?(model_id),
          tool: Monadic::Utils::ModelSpec.tool_capability?(model_id),
          reasoning: Monadic::Utils::ModelSpec.is_reasoning_model?(model_id),
          deprecated: Monadic::Utils::ModelSpec.deprecated?(model_id)
        }
      rescue StandardError
        { id: model_id, known: false }
      end

      # context_window / max_output_tokens are stored as [min, max] in the spec.
      def numeric_max(value)
        value.is_a?(Array) ? value.last : value
      end

      def truthy?(value)
        value == true || value.to_s.strip.downcase == "true"
      end
    end
  end
end
