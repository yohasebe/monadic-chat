# frozen_string_literal: true

require 'json'
require_relative 'cost_guard'
require_relative '../agents/second_opinion_agent'
require_relative '../agents/image_analysis_agent'

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
      PARALLEL_TIMEOUT = 180

      # Memoized headless provider hosts (see provider_host).
      @provider_hosts = {}
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
                  description: "Optional model id. Defaults to the provider's chat default."
                },
                max_tokens: {
                  type: "integer",
                  description: "Optional cap on output tokens (default #{DEFAULT_MAX_OUTPUT})."
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
            description: "Fan the same query out to 2-#{MAX_PARALLEL_PROVIDERS} providers " \
                         "concurrently and return all responses together. Lets a CLI agent " \
                         "compare or cross-check answers across providers without writing its " \
                         "own concurrency. Each sub-query spends tokens and is gated by the " \
                         "platform token budget. Provide `message` or `messages`.",
            input_schema: {
              type: "object",
              properties: {
                providers: {
                  type: "array",
                  description: "2-#{MAX_PARALLEL_PROVIDERS} provider names to query in parallel.",
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
                  description: "Optional per-provider output cap (default #{DEFAULT_MAX_OUTPUT})."
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
              required: ["providers"],
              additionalProperties: false
            },
            handler: :handle_parallel_query
          },
          {
            name: "monadic_second_opinion",
            description: "Ask one or more providers to critically verify a query/response pair " \
                         "and return a validity score (1-10) plus critique — Monadic's " \
                         "second-opinion sub-agent. Use it to cross-check an answer (your own " \
                         "or another model's) before trusting it. Give `provider` for a single " \
                         "evaluator, or `providers` (2-#{MAX_PARALLEL_PROVIDERS}) to verify in " \
                         "parallel. Spends tokens; gated by the platform token budget.",
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
        providers_arg = arguments["providers"] || arguments[:providers]
        unless providers_arg.is_a?(Array) && providers_arg.size.between?(2, MAX_PARALLEL_PROVIDERS)
          raise ArgumentError,
                "providers must be an array of 2-#{MAX_PARALLEL_PROVIDERS} provider names"
        end

        messages = normalize_messages(arguments)
        raise ArgumentError, "provide either `message` or `messages`" if messages.empty?

        system = (arguments["system"] || arguments[:system]).to_s
        max_output = (arguments["max_tokens"] || arguments[:max_tokens])
        temperature = arguments["temperature"] || arguments[:temperature]
        models = arguments["models"] || arguments[:models] || {}
        knowledge_base = arguments["knowledge_base"] || arguments[:knowledge_base]
        privacy = arguments["privacy"] || arguments[:privacy]

        # Canonicalize and de-duplicate so the same provider's (shared) app
        # instance is never driven by two concurrent threads.
        targets = providers_arg.each_with_object([]) do |raw, acc|
          original = raw.to_s
          canonical = MonadicDSL::ProviderConfig.new(original).standard_key
          next if acc.any? { |t| t[:provider] == canonical }
          acc << { provider: canonical, model: (models[original] || models[canonical]) }
        end

        results = run_in_parallel(targets) do |target|
          execute_query(
            provider: target[:provider],
            messages: messages,
            system: system,
            model: target[:model],
            max_output: max_output,
            temperature: temperature,
            knowledge_base: knowledge_base,
            privacy: privacy
          )
        end

        { results: results, budget: CostGuard.status }
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

        result = vision_host(provider).image_analysis_agent(message: prompt, image_path: path)
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

      # Host mixing in ImageAnalysisAgent. The agent reads settings["provider"]
      # to prefer a vision provider, so we supply a minimal settings carrying the
      # (optional) requested provider; an empty value triggers the agent's own
      # first-available fallback.
      def vision_host(provider)
        klass = Class.new do
          include ImageAnalysisAgent
          attr_accessor :_conduit_provider
          def settings
            { "provider" => _conduit_provider.to_s }
          end
        end
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

        output_tokens = CostGuard.estimate_tokens(normalized[:text] || normalized[:error])
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
              { provider: target[:provider], success: false, error: "❌ #{e.class}: #{e.message}" }
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

        @hosts_mutex.synchronize do
          @provider_hosts[provider] ||= begin
            helper = Object.const_get(helper_name)
            Class.new.tap { |klass| klass.include(helper) }.new
          end
        end
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
