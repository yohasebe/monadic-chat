# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/model_spec"
require_relative "../../../lib/monadic/utils/container_dependencies"
require_relative "../../../lib/monadic/utils/privacy/pipeline"
require_relative "../../../lib/monadic/mcp/conduit"

RSpec.describe Monadic::MCP::Conduit do
  describe ".tools" do
    subject(:tools) { described_class.tools }

    it "exposes the capability tools" do
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly(
        "monadic_status", "monadic_list_models", "monadic_query",
        "monadic_parallel_query", "monadic_second_opinion",
        "monadic_search_kb", "monadic_list_kb", "monadic_import_kb"
      )
    end

    it "publishes monadic_* names only (no app__tool surface)" do
      expect(tools).to all(include(:name => a_string_matching(/\Amonadic_/)))
      expect(tools.map { |t| t[:name] }).to all(satisfy { |n| !n.include?("__") })
    end

    it "provides a valid JSON-Schema inputSchema for each tool" do
      tools.each do |tool|
        expect(tool[:inputSchema]).to include(type: "object")
        expect(tool[:description]).to be_a(String)
        expect(tool[:description]).not_to be_empty
      end
    end
  end

  describe ".tool?" do
    it "recognizes Conduit tools and rejects others" do
      expect(described_class.tool?("monadic_status")).to be true
      expect(described_class.tool?("monadic_list_models")).to be true
      expect(described_class.tool?("monadic_query")).to be true
      expect(described_class.tool?("monadic_parallel_query")).to be true
      expect(described_class.tool?("monadic_second_opinion")).to be true
      expect(described_class.tool?("monadic_search_kb")).to be true
      expect(described_class.tool?("monadic_list_kb")).to be true
      expect(described_class.tool?("monadic_import_kb")).to be true
      expect(described_class.tool?("Chat__some_tool")).to be false
      expect(described_class.tool?("nonexistent")).to be false
    end
  end

  describe ".call" do
    it "raises for an unknown tool" do
      expect { described_class.call("nope") }.to raise_error(/Unknown Conduit tool/)
    end
  end

  describe "monadic_status" do
    subject(:status) { described_class.call("monadic_status", {}) }

    before do
      allow(Monadic::Utils::ContainerDependencies)
        .to receive(:container_running?).and_return(false)
    end

    it "reports backend identity and execution mode" do
      expect(status[:backend][:name]).to eq("monadic-chat")
      expect(status[:backend][:version]).to be_a(String)
      expect(%w[host container unknown]).to include(status[:backend][:mode])
    end

    it "lists every known provider with a configured flag" do
      provider_names = status[:providers].map { |p| p[:provider] }
      expect(provider_names).to include("openai", "anthropic", "gemini", "ollama")
      status[:providers].each do |p|
        expect([true, false]).to include(p[:configured])
      end
    end

    it "treats keyless providers (ollama) as configured" do
      ollama = status[:providers].find { |p| p[:provider] == "ollama" }
      expect(ollama[:configured]).to be true
    end

    it "reflects API-key presence from CONFIG" do
      stub_const("CONFIG", CONFIG.merge("OPENAI_API_KEY" => "sk-test"))
      openai = described_class.call("monadic_status", {})[:providers]
                             .find { |p| p[:provider] == "openai" }
      expect(openai[:configured]).to be true
    end

    it "reports each dependent container's running state" do
      services = status[:containers].map { |c| c[:service] }
      expect(services).to include("python", "qdrant", "embeddings")
      status[:containers].each do |c|
        expect(c).to include(:container, :running)
      end
    end

    it "surfaces the Conduit token budget" do
      expect(status[:conduit_budget]).to include(
        :token_budget, :tokens_spent, :tokens_remaining
      )
    end
  end

  describe "monadic_query" do
    let(:host) { double("ChatApp") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:provider_host).and_return(host)
      allow(described_class).to receive(:default_chat_model_for).and_return("test-model")
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "sends a single message and returns normalized text + usage + budget" do
      expect(host).to receive(:send_query)
        .with(hash_including("messages", "model" => "test-model"), model: "test-model")
        .and_return("Hello from the provider")

      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "Hi" })

      expect(result[:provider]).to eq("openai")
      expect(result[:success]).to be true
      expect(result[:text]).to eq("Hello from the provider")
      expect(result[:usage]).to include(:input_tokens_est, :output_tokens_est)
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "resolves provider aliases (claude -> anthropic)" do
      allow(host).to receive(:send_query).and_return("ok")
      result = described_class.call("monadic_query",
                                    { "provider" => "claude", "message" => "Hi" })
      expect(result[:provider]).to eq("anthropic")
    end

    it "accepts a full messages array" do
      expect(host).to receive(:send_query) do |body, **_|
        expect(body["messages"]).to eq([
          { "role" => "system", "content" => "be terse" },
          { "role" => "user", "content" => "hi" }
        ])
        "ok"
      end
      described_class.call("monadic_query", {
        "provider" => "openai",
        "messages" => [
          { "role" => "system", "content" => "be terse" },
          { "role" => "user", "content" => "hi" }
        ]
      })
    end

    it "normalizes a tool-call hash response" do
      allow(host).to receive(:send_query)
        .and_return({ text: "calling tool", tool_calls: [{ name: "foo" }] })
      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "Hi" })
      expect(result[:success]).to be true
      expect(result[:text]).to eq("calling tool")
      expect(result[:tool_calls]).to eq([{ name: "foo" }])
    end

    it "detects an ErrorFormatter error string as failure" do
      allow(host).to receive(:send_query)
        .and_return("[OpenAI] API Error: invalid key (Code: 401)")
      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "Hi" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/API Error/)
    end

    it "refuses to spend when the budget is exhausted (hard ceiling)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "5"))
      expect(host).not_to receive(:send_query)
      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "a long enough prompt" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end

    it "requires a provider" do
      expect { described_class.call("monadic_query", { "message" => "hi" }) }
        .to raise_error(ArgumentError, /provider is required/)
    end

    it "requires message or messages" do
      expect { described_class.call("monadic_query", { "provider" => "openai" }) }
        .to raise_error(ArgumentError, /message/)
    end

    it "errors when no vendor helper is available for the provider" do
      allow(described_class).to receive(:provider_host).and_return(nil)
      expect { described_class.call("monadic_query", { "provider" => "openai", "message" => "hi" }) }
        .to raise_error(/no vendor helper available/)
    end
  end

  describe ".provider_host" do
    it "builds a headless host that responds to send_query, without borrowing an app" do
      host = described_class.provider_host("openai")
      expect(host).to respond_to(:send_query)
      # It is NOT a MonadicApp (no app borrowed) — just a helper-bearing object.
      expect(host).not_to respond_to(:settings)
    end

    it "memoizes one host per provider" do
      expect(described_class.provider_host("anthropic"))
        .to be(described_class.provider_host("anthropic"))
    end

    it "returns nil for an unknown provider" do
      expect(described_class.provider_host("nonsense-provider")).to be_nil
    end
  end

  describe "monadic_parallel_query" do
    let(:host) { double("ChatApp") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:provider_host).and_return(host)
      allow(described_class).to receive(:default_chat_model_for) { |p| "#{p}-default" }
      allow(host).to receive(:send_query).and_return("answer")
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "fans out to each provider and aggregates results" do
      result = described_class.call("monadic_parallel_query", {
        "providers" => %w[openai anthropic gemini],
        "message" => "What is 2+2?"
      })
      providers = result[:results].map { |r| r[:provider] }
      expect(providers).to contain_exactly("openai", "anthropic", "gemini")
      expect(result[:results]).to all(include(success: true, text: "answer"))
      expect(result[:budget]).to include(:tokens_spent)
    end

    it "canonicalizes and de-duplicates providers (claude == anthropic)" do
      result = described_class.call("monadic_parallel_query", {
        "providers" => %w[claude anthropic openai],
        "message" => "hi"
      })
      providers = result[:results].map { |r| r[:provider] }
      expect(providers).to contain_exactly("anthropic", "openai")
    end

    it "applies per-provider model overrides" do
      expect(host).to receive(:send_query)
        .with(hash_including("model" => "gpt-x"), model: "gpt-x").and_return("a")
      expect(host).to receive(:send_query)
        .with(hash_including("model" => "anthropic-default"), model: "anthropic-default")
        .and_return("b")
      described_class.call("monadic_parallel_query", {
        "providers" => %w[openai anthropic],
        "message" => "hi",
        "models" => { "openai" => "gpt-x" }
      })
    end

    it "isolates a failing provider without aborting the others" do
      allow(described_class).to receive(:execute_query) do |provider:, **_|
        raise "boom" if provider == "gemini"
        { provider: provider, success: true, text: "ok" }
      end
      result = described_class.call("monadic_parallel_query", {
        "providers" => %w[openai gemini],
        "message" => "hi"
      })
      gemini = result[:results].find { |r| r[:provider] == "gemini" }
      openai = result[:results].find { |r| r[:provider] == "openai" }
      expect(openai[:success]).to be true
      expect(gemini[:success]).to be false
      expect(gemini[:error]).to match(/boom/)
    end

    it "rejects fewer than 2 providers" do
      expect { described_class.call("monadic_parallel_query", { "providers" => ["openai"], "message" => "hi" }) }
        .to raise_error(ArgumentError, /2-/)
    end

    it "rejects more than the max providers" do
      too_many = %w[openai anthropic gemini cohere mistral deepseek]
      expect { described_class.call("monadic_parallel_query", { "providers" => too_many, "message" => "hi" }) }
        .to raise_error(ArgumentError, /2-/)
    end
  end

  describe "monadic_second_opinion" do
    let(:agent_host) { double("SecondOpinionHost") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:second_opinion_host).and_return(agent_host)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "runs a single evaluator and returns validity + comments + budget" do
      expect(agent_host).to receive(:second_opinion_agent)
        .with(hash_including(user_query: "2+2?", agent_response: "5", provider: "openai"))
        .and_return({ comments: "Incorrect, 2+2=4", validity: "2/10", model: "openai:gpt-5.4" })

      result = described_class.call("monadic_second_opinion", {
        "user_query" => "2+2?", "agent_response" => "5", "provider" => "openai"
      })

      expect(result[:provider]).to eq("openai")
      expect(result[:validity]).to eq("2/10")
      expect(result[:comments]).to match(/Incorrect/)
      expect(result[:success]).to be true
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "marks an evaluator error result as failure" do
      allow(agent_host).to receive(:second_opinion_agent)
        .and_return({ comments: "Error: Model not specified", validity: "error", model: "none" })
      result = described_class.call("monadic_second_opinion", {
        "user_query" => "q", "agent_response" => "a", "provider" => "openai"
      })
      expect(result[:success]).to be false
    end

    it "verifies across multiple providers in parallel" do
      allow(agent_host).to receive(:second_opinion_agent) do |provider:, **_|
        { comments: "checked by #{provider}", validity: "8/10", model: "#{provider}:m" }
      end
      result = described_class.call("monadic_second_opinion", {
        "user_query" => "q", "agent_response" => "a",
        "providers" => %w[openai claude]
      })
      providers = result[:results].map { |r| r[:provider] }
      expect(providers).to contain_exactly("openai", "anthropic")
      expect(result[:results]).to all(include(success: true))
    end

    it "requires user_query and agent_response" do
      expect { described_class.call("monadic_second_opinion", { "agent_response" => "a" }) }
        .to raise_error(ArgumentError, /user_query/)
      expect { described_class.call("monadic_second_opinion", { "user_query" => "q" }) }
        .to raise_error(ArgumentError, /agent_response/)
    end

    it "refuses when the budget is exhausted" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(agent_host).not_to receive(:second_opinion_agent)
      result = described_class.call("monadic_second_opinion", {
        "user_query" => "a longer query here", "agent_response" => "a response", "provider" => "openai"
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_list_models" do
    it "returns providers each with categories and enriched models" do
      result = described_class.call("monadic_list_models", {})
      expect(result[:providers]).to be_an(Array)
      expect(result[:providers]).not_to be_empty

      openai = result[:providers].find { |p| p[:provider] == "openai" }
      expect(openai[:categories]).to be_a(Hash)
      expect(openai[:models]).to be_an(Array)
      expect(openai[:models]).not_to be_empty

      model = openai[:models].first
      expect(model).to include(:id, :known)
      if model[:known]
        expect(model).to include(:context_window, :vision, :tool, :reasoning, :deprecated)
        expect([true, false]).to include(model[:vision], model[:tool])
      end
    end

    it "filters by provider and accepts aliases" do
      result = described_class.call("monadic_list_models", { "provider" => "claude" })
      providers = result[:providers].map { |p| p[:provider] }
      expect(providers).to eq(["anthropic"])
    end

    it "excludes deprecated models by default" do
      result = described_class.call("monadic_list_models", {})
      all_models = result[:providers].flat_map { |p| p[:models] }
      expect(all_models.any? { |m| m[:deprecated] }).to be false
    end

    it "includes deprecated models when requested" do
      # Inject a deprecated model into a provider's chat list to verify the flag
      # is honored without depending on the live spec containing one.
      allow(Monadic::Utils::ModelSpec).to receive(:load_provider_defaults)
        .and_return({ "openai" => { "chat" => ["__dep_model__"] } })
      allow(Monadic::Utils::ModelSpec).to receive(:get_model_spec)
        .with("__dep_model__").and_return({ "deprecated" => true })
      allow(Monadic::Utils::ModelSpec).to receive(:deprecated?)
        .with("__dep_model__").and_return(true)
      allow(Monadic::Utils::ModelSpec).to receive(:vision_capability?).and_return(false)
      allow(Monadic::Utils::ModelSpec).to receive(:tool_capability?).and_return(false)
      allow(Monadic::Utils::ModelSpec).to receive(:is_reasoning_model?).and_return(false)

      excluded = described_class.call("monadic_list_models", { "provider" => "openai" })
      included = described_class.call(
        "monadic_list_models", { "provider" => "openai", "include_deprecated" => true }
      )

      excluded_ids = excluded[:providers].first[:models].map { |m| m[:id] }
      included_ids = included[:providers].first[:models].map { |m| m[:id] }

      expect(excluded_ids).not_to include("__dep_model__")
      expect(included_ids).to include("__dep_model__")
    end
  end

  describe "knowledge base tools" do
    let(:store) { double("PdfStore") }

    before { allow(described_class).to receive(:kb_store).and_return(store) }

    describe "monadic_search_kb" do
      it "searches text chunks and returns hits with the namespace" do
        expect(store).to receive(:find_closest_text).with("neural nets", top_n: 5)
          .and_return([{ text: "chunk A", similarity: 0.9, doc_id: "d1" }])
        result = described_class.call("monadic_search_kb", { "query" => "neural nets" })
        expect(result[:knowledge_base]).to eq("global")
        expect(result[:level]).to eq("item")
        expect(result[:count]).to eq(1)
        expect(result[:results].first[:text]).to eq("chunk A")
      end

      it "honors a custom namespace, top_n and doc level" do
        expect(described_class).to receive(:kb_store).with("papers").and_return(store)
        expect(store).to receive(:find_closest_doc).with("q", top_n: 3).and_return([])
        result = described_class.call("monadic_search_kb", {
          "query" => "q", "knowledge_base" => "papers", "top_n" => 3, "level" => "doc"
        })
        expect(result[:level]).to eq("doc")
      end

      it "requires a query" do
        expect { described_class.call("monadic_search_kb", {}) }
          .to raise_error(ArgumentError, /query is required/)
      end

      it "returns a structured error when the vector store is down" do
        allow(store).to receive(:find_closest_text)
          .and_raise(Monadic::VectorStore::BackendError.new("connection refused"))
        result = described_class.call("monadic_search_kb", { "query" => "q" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Knowledge Base unavailable/)
      end
    end

    describe "monadic_list_kb" do
      it "lists stored documents" do
        allow(store).to receive(:list_titles)
          .and_return([{ doc_id: "d1", title: "Paper", items: 12 }])
        result = described_class.call("monadic_list_kb", { "knowledge_base" => "papers" })
        expect(result[:knowledge_base]).to eq("papers")
        expect(result[:count]).to eq(1)
        expect(result[:documents].first[:title]).to eq("Paper")
      end
    end

    describe "monadic_import_kb" do
      it "imports raw text: chunks, stores, and reports the doc_id" do
        expect(store).to receive(:store_embeddings) do |doc_data, items_data|
          expect(doc_data[:title]).to eq("Notes")
          expect(items_data).to all(include(:text))
          "doc-123"
        end
        result = described_class.call("monadic_import_kb", {
          "title" => "Notes", "text" => "line one\nline two\nline three"
        })
        expect(result[:doc_id]).to eq("doc-123")
        expect(result[:title]).to eq("Notes")
        expect(result[:chunks]).to be > 0
        expect(result[:source]).to eq("text")
      end

      it "requires a title" do
        expect { described_class.call("monadic_import_kb", { "text" => "x" }) }
          .to raise_error(ArgumentError, /title is required/)
      end

      it "requires text or path" do
        expect { described_class.call("monadic_import_kb", { "title" => "T" }) }
          .to raise_error(ArgumentError, /text.*or.*path/)
      end

      it "rejects a non-pdf path" do
        expect { described_class.call("monadic_import_kb", { "title" => "T", "path" => "/tmp/foo.txt" }) }
          .to raise_error(ArgumentError, /must point to a \.pdf/)
      end
    end
  end

  describe ".chunk_text" do
    it "splits text into chunks with text + token fields" do
      chunks = described_class.chunk_text("a\nb\nc\nd", max_tokens: 1)
      expect(chunks).not_to be_empty
      expect(chunks).to all(include("text"))
    end
  end

  describe "monadic_query grounding (knowledge_base)" do
    let(:host) { double("host") }
    let(:store) { double("store") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:provider_host).and_return(host)
      allow(described_class).to receive(:default_chat_model_for).and_return("m")
      allow(described_class).to receive(:kb_store).and_return(store)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "injects KB context into the system prompt and flags grounded" do
      allow(store).to receive(:find_closest_text).with("explain X", top_n: 4)
        .and_return([{ text: "X is a documented thing" }])
      captured = nil
      allow(host).to receive(:send_query) { |body, **| captured = body; "answer" }

      result = described_class.call("monadic_query", {
        "provider" => "openai", "message" => "explain X", "knowledge_base" => "kb1"
      })

      # Context is folded into the user turn (uniform cross-provider delivery).
      user_msg = captured["messages"].last["content"]
      expect(user_msg).to include("X is a documented thing")
      expect(user_msg).to include("explain X")
      expect(result[:grounded]).to be true
      expect(result[:success]).to be true
    end

    it "fails closed when the KB is unavailable" do
      allow(store).to receive(:find_closest_text)
        .and_raise(Monadic::VectorStore::BackendError.new("connection refused"))
      expect(host).not_to receive(:send_query)
      result = described_class.call("monadic_query", {
        "provider" => "openai", "message" => "q", "knowledge_base" => "kb1"
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Knowledge Base unavailable/)
    end
  end

  describe "monadic_query privacy" do
    let(:host) { double("host") }
    let(:pipeline) { double("pipeline") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:provider_host).and_return(host)
      allow(described_class).to receive(:default_chat_model_for).and_return("m")
      allow(described_class).to receive(:build_privacy_pipeline).and_return(pipeline)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "masks the outgoing message, restores the response, and flags privacy" do
      allow(pipeline).to receive(:before_send_to_llm)
        .and_return(double(text: "Hi <<PERSON_1>>"))
      allow(pipeline).to receive(:after_receive_from_llm)
        .with("Reply to <<PERSON_1>>").and_return(double(text: "Reply to John"))
      captured = nil
      allow(host).to receive(:send_query) { |body, **| captured = body; "Reply to <<PERSON_1>>" }

      result = described_class.call("monadic_query", {
        "provider" => "openai", "message" => "Hi John", "privacy" => true
      })

      expect(captured["messages"].first["content"]).to eq("Hi <<PERSON_1>>")
      expect(result[:text]).to eq("Reply to John")
      expect(result[:privacy]).to be true
    end

    it "fails closed when the masking backend is down" do
      allow(pipeline).to receive(:before_send_to_llm)
        .and_raise(Monadic::Utils::Privacy::BackendError.new("presidio unreachable"))
      expect(host).not_to receive(:send_query)
      result = described_class.call("monadic_query", {
        "provider" => "openai", "message" => "Hi John", "privacy" => true
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Privacy masking unavailable/)
    end
  end
end
