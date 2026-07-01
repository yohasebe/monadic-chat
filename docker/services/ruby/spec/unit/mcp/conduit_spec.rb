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
        "monadic_parallel_query", "monadic_second_opinion", "monadic_confidence",
        "monadic_search_kb", "monadic_list_kb", "monadic_import_kb",
        "monadic_analyze_image", "monadic_transcribe_audio",
        "monadic_analyze_audio", "monadic_analyze_video",
        "monadic_speak", "monadic_generate_code", "monadic_generate_image",
        "monadic_generate_video", "monadic_generate_music", "monadic_agent",
        "monadic_submit", "monadic_poll", "monadic_cancel", "monadic_jobs"
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
      expect(described_class.tool?("monadic_analyze_image")).to be true
      expect(described_class.tool?("monadic_transcribe_audio")).to be true
      expect(described_class.tool?("monadic_analyze_audio")).to be true
      expect(described_class.tool?("monadic_analyze_video")).to be true
      expect(described_class.tool?("monadic_speak")).to be true
      expect(described_class.tool?("monadic_generate_code")).to be true
      expect(described_class.tool?("monadic_generate_image")).to be true
      expect(described_class.tool?("monadic_generate_video")).to be true
      expect(described_class.tool?("monadic_generate_music")).to be true
      expect(described_class.tool?("monadic_agent")).to be true
      expect(described_class.tool?("monadic_submit")).to be true
      expect(described_class.tool?("monadic_poll")).to be true
      expect(described_class.tool?("monadic_cancel")).to be true
      expect(described_class.tool?("monadic_jobs")).to be true
      expect(described_class.tool?("Chat__some_tool")).to be false
      expect(described_class.tool?("nonexistent")).to be false
    end
  end

  describe ".call" do
    it "raises for an unknown tool" do
      expect { described_class.call("nope") }.to raise_error(/Unknown Conduit tool/)
    end
  end

  describe "monadic_query empty-output diagnostics" do
    let(:host) { double("host") }

    before { allow(described_class).to receive(:provider_host).and_return(host) }

    it "flags empty visible output with empty_output + an actionable warning" do
      allow(host).to receive(:send_query).and_return("")
      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "hi", "max_tokens" => 100 })
      expect(result[:success]).to be true
      expect(result[:empty_output]).to be true
      expect(result[:warning]).to match(/empty output/i)
      expect(result[:warning]).to match(/max_tokens/)
    end

    it "adds no empty_output/warning when the model returns text" do
      allow(host).to receive(:send_query).and_return("A complete answer.")
      result = described_class.call("monadic_query",
                                    { "provider" => "openai", "message" => "hi" })
      expect(result[:success]).to be true
      expect(result).not_to have_key(:empty_output) # nil compacted away
      expect(result).not_to have_key(:warning)
    end
  end

  describe "monadic_query reasoning_effort passthrough" do
    let(:host) { double("host") }

    before { allow(described_class).to receive(:provider_host).and_return(host) }

    it "forwards reasoning_effort into the send_query body" do
      captured = nil
      allow(host).to receive(:send_query) { |body, **| captured = body; "answer." }
      described_class.call("monadic_query",
                           { "provider" => "openai", "message" => "hi", "reasoning_effort" => "low" })
      expect(captured["reasoning_effort"]).to eq("low")
    end

    it "omits reasoning_effort from the body when not provided" do
      captured = nil
      allow(host).to receive(:send_query) { |body, **| captured = body; "answer." }
      described_class.call("monadic_query", { "provider" => "openai", "message" => "hi" })
      expect(captured).not_to have_key("reasoning_effort")
    end

    it "advertises reasoning_effort in the monadic_query tool schema" do
      tool = described_class.tools.find { |t| t[:name] == "monadic_query" }
      props = tool.dig(:inputSchema, :properties) || tool.dig("inputSchema", "properties")
      expect(props).to have_key(:reasoning_effort).or have_key("reasoning_effort")
    end
  end

  describe "monadic_query provider usage surfacing" do
    let(:host) { double("host") }

    before { allow(described_class).to receive(:provider_host).and_return(host) }

    it "surfaces real provider usage when the helper reports it (thread-local)" do
      allow(host).to receive(:send_query) do |_body, **|
        Thread.current[:conduit_provider_usage] =
          { input: 100, output: 20, reasoning: 8, cached: 0, total: 120 }
        "answer."
      end
      result = described_class.call("monadic_query", { "provider" => "openai", "message" => "hi" })
      expect(result[:provider_usage]).to eq(input: 100, output: 20, reasoning: 8, cached: 0, total: 120)
    end

    it "omits provider_usage (and does not leak a stale value) when unreported" do
      Thread.current[:conduit_provider_usage] = { input: 999 } # stale from a prior call
      allow(host).to receive(:send_query) { |_b, **| "answer." } # reports nothing
      result = described_class.call("monadic_query", { "provider" => "cohere", "message" => "hi" })
      expect(result).not_to have_key(:provider_usage)
    end
  end

  describe ".empty_output_warning" do
    it "names reasoning + the budget for reasoning models" do
      allow(Monadic::Utils::ModelSpec).to receive(:is_reasoning_model?).and_return(true)
      msg = described_class.empty_output_warning("gpt-5.5", 6000)
      expect(msg).to match(/reasoning/i)
      expect(msg).to match(/6000/)
      expect(msg).to match(/max_tokens/)
    end

    it "gives a generic increase-max_tokens hint for non-reasoning models" do
      allow(Monadic::Utils::ModelSpec).to receive(:is_reasoning_model?).and_return(false)
      msg = described_class.empty_output_warning("some-model", 4096)
      expect(msg).to match(/max_tokens/)
      expect(msg).not_to match(/reasoning/i)
    end
  end

  describe "monadic_confidence" do
    describe ".confidence_band" do
      it "maps scores to calibrated bands + actions" do
        expect(described_class.confidence_band(0.9)).to eq(level: "high", action: "trust")
        expect(described_class.confidence_band(0.8)).to eq(level: "high", action: "trust")
        expect(described_class.confidence_band(0.6)).to eq(level: "medium", action: "verify")
        expect(described_class.confidence_band(0.3)).to eq(level: "low", action: "escalate")
      end

      it "returns unknown/verify for a non-numeric score" do
        expect(described_class.confidence_band(nil)).to eq(level: "unknown", action: "verify")
      end
    end

    describe ".parse_consensus" do
      it "extracts a JSON verdict embedded in prose and clamps the score" do
        text = %(Here is my assessment: {"score": 1.5, "consensus": "42", ) +
               %("disagreements": ["units"]} done)
        v = described_class.parse_consensus(text)
        expect(v[:score]).to eq(1.0) # clamped to [0,1]
        expect(v[:consensus]).to eq("42")
        expect(v[:disagreements]).to eq(["units"])
      end

      it "yields a neutral verdict (nil score) on malformed output" do
        v = described_class.parse_consensus("no json here")
        expect(v[:score]).to be_nil
        expect(v[:disagreements]).to eq([])
      end

      it "skips a brace-containing preamble and finds the real score object" do
        text = %(Comparing {Response 1} and {Response 2}: {"score": 0.8, "consensus": "x", ) +
               %("disagreements": []})
        expect(described_class.parse_consensus(text)[:score]).to eq(0.8)
      end

      it "coerces a stringified score (LLMs often quote numbers)" do
        expect(described_class.parse_consensus(%({"score": "0.7"}))[:score]).to eq(0.7)
      end

      it "extracts review_aligns when present (corroboration mode)" do
        v = described_class.parse_consensus(%({"score": 0.9, "review_aligns": "disputed"}))
        expect(v[:review_aligns]).to eq("disputed")
      end

      it "leaves review_aligns nil when absent (plain agreement mode)" do
        expect(described_class.parse_consensus(%({"score": 0.9}))[:review_aligns]).to be_nil
      end
    end

    describe ".handle_confidence" do
      let(:ok_openai)    { { provider: "openai", model: "m1", success: true, text: "42." } }
      let(:ok_anthropic) { { provider: "anthropic", model: "m2", success: true, text: "42." } }

      it "assembles a verdict; cross_provider reflects the SURVIVING providers" do
        allow(described_class).to receive(:execute_query).and_return(ok_openai, ok_anthropic)
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: 0.9, consensus: "42", disagreements: [])
        result = described_class.call("monadic_confidence",
                                      { "providers" => %w[openai anthropic], "message" => "6*7?" })
        expect(result[:confidence]).to eq("high")
        expect(result[:recommendation]).to eq("trust")
        expect(result[:panel_size]).to eq(2)
        expect(result[:cross_provider]).to be true
      end

      it "does NOT claim cross_provider when a provider drops and survivors share one" do
        # anthropic errors -> both usable answers are openai -> weak, not cross.
        allow(described_class).to receive(:execute_query)
          .and_return(ok_openai, { provider: "openai", model: "m1b", success: true, text: "42." })
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: 0.9, consensus: "42", disagreements: [])
        result = described_class.call("monadic_confidence",
                                      { "targets" => [{ "provider" => "openai" }, { "provider" => "anthropic" }],
                                        "message" => "6*7?" })
        expect(result[:cross_provider]).to be false
        expect(result[:note]).to match(/single provider/i)
      end

      it "returns unknown when fewer than two members succeed" do
        allow(described_class).to receive(:execute_query)
          .and_return(ok_openai, { provider: "anthropic", success: false, error: "❌ down" })
        result = described_class.call("monadic_confidence",
                                      { "providers" => %w[openai anthropic], "message" => "hi" })
        expect(result[:confidence]).to eq("unknown")
        expect(result[:note]).to match(/Need >= 2/)
      end

      it "escalates a DISPUTED reviewed answer even when the panel agrees (corroboration)" do
        allow(described_class).to receive(:execute_query).and_return(ok_openai, ok_anthropic)
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: 0.9, consensus: "42", disagreements: [], review_aligns: "disputed")
        result = described_class.call("monadic_confidence",
                                      { "providers" => %w[openai anthropic], "message" => "6*7?",
                                        "review_answer" => "The answer is 41." })
        expect(result[:confidence]).to eq("high")          # panel itself agrees
        expect(result[:corroboration]).to eq("disputed")    # but the reviewed answer is an outlier
        expect(result[:recommendation]).to eq("escalate")   # so don't trust it
      end

      it "surfaces judge_error so a failed judge isn't read as 'no consensus'" do
        allow(described_class).to receive(:execute_query).and_return(ok_openai, ok_anthropic)
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: nil, consensus: "", disagreements: [], judge_error: "❌ Budget exceeded")
        result = described_class.call("monadic_confidence",
                                      { "providers" => %w[openai anthropic], "message" => "hi" })
        expect(result[:confidence]).to eq("unknown")
        expect(result[:judge_error]).to match(/Budget/)
      end

      it "AUTO-selects the panel via the ladder when no targets/providers are given" do
        allow(described_class).to receive(:select_confidence_panel)
          .and_return(mode: :cross_provider, signal: :strong,
                      targets: [{ provider: "openai", model: "m1" }, { provider: "anthropic", model: "m2" }])
        allow(described_class).to receive(:execute_query).and_return(ok_openai, ok_anthropic)
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: 0.85, consensus: "42", disagreements: [])
        result = described_class.call("monadic_confidence", { "message" => "6*7?" })
        expect(result[:confidence]).to eq("high")
      end

      it "runs within-provider self-consistency (K samples) for a single provider" do
        allow(described_class).to receive(:select_confidence_panel)
          .and_return(mode: :within_provider, signal: :weak,
                      targets: [{ provider: "openai", model: "m1" }], samples: 3)
        # Must fan out 3 times (K samples), not once -> 3 usable responses.
        expect(described_class).to receive(:fan_out_panel) do |_msgs, targets, _args, **_kw|
          expect(targets.size).to eq(3)
          targets.map { |t| t.merge(success: true, text: "42.") }
        end
        allow(described_class).to receive(:judge_consensus)
          .and_return(score: 0.9, consensus: "42", disagreements: [])
        result = described_class.call("monadic_confidence", { "message" => "6*7?" })
        expect(result[:confidence]).to eq("high")
        expect(result[:cross_provider]).to be false # same provider -> weak signal
      end

      it "refuses (unavailable) WITHOUT fanning out when the ladder can't measure" do
        allow(described_class).to receive(:select_confidence_panel)
          .and_return(mode: :unavailable, signal: :none, targets: [], reason: "single deterministic model")
        expect(described_class).not_to receive(:execute_query)
        result = described_class.call("monadic_confidence", { "message" => "hi" })
        expect(result[:confidence]).to eq("unavailable")
        expect(result[:note]).to match(/deterministic/)
      end
    end

    describe ".judge_consensus" do
      it "sets judge_error when the judge query fails (execute_query returns success:false)" do
        allow(described_class).to receive(:execute_query)
          .and_return(provider: "openai", success: false, error: "❌ Budget exceeded")
        v = described_class.judge_consensus("q", [{ text: "a" }, { text: "b" }], nil)
        expect(v[:score]).to be_nil
        expect(v[:judge_error]).to match(/Budget/)
      end

      it "parses a valid judge verdict and reports the moderator identity" do
        allow(described_class).to receive(:default_chat_model_for).and_return("judge-model")
        allow(described_class).to receive(:execute_query)
          .and_return(provider: "openai", success: true, text: %({"score": 0.9, "consensus": "42", "disagreements": []}))
        v = described_class.judge_consensus("q", [{ text: "a" }, { text: "b" }], nil)
        expect(v[:score]).to eq(0.9)
        expect(v[:judge_error]).to be_nil
        expect(v[:judge_provider]).to eq("openai")
        expect(v[:judge_model]).to eq("judge-model")
      end
    end

    describe ".select_confidence_panel (graceful-degradation ladder)" do
      def stub_usable(list)
        allow(described_class).to receive(:usable_chat_providers).and_return(list)
      end

      it "cross-provider (strong) when >=2 distinct providers, capped at 3" do
        stub_usable([{ provider: "openai", model: "a" }, { provider: "anthropic", model: "b" },
                     { provider: "gemini", model: "c" }, { provider: "xai", model: "d" }])
        p = described_class.select_confidence_panel
        expect(p[:mode]).to eq(:cross_provider)
        expect(p[:signal]).to eq(:strong)
        expect(p[:targets].size).to eq(3) # capped
      end

      it "within-provider self-consistency (weak) when exactly 1 samplable provider" do
        stub_usable([{ provider: "openai", model: "samplable" }])
        allow(described_class).to receive(:sampling_capable?).and_return(true)
        p = described_class.select_confidence_panel
        expect(p[:mode]).to eq(:within_provider)
        expect(p[:signal]).to eq(:weak)
        expect(p[:samples]).to be >= 2
      end

      it "UNAVAILABLE (no false signal) when the lone model is deterministic" do
        stub_usable([{ provider: "openai", model: "deterministic" }])
        allow(described_class).to receive(:sampling_capable?).and_return(false)
        p = described_class.select_confidence_panel
        expect(p[:mode]).to eq(:unavailable)
        expect(p[:signal]).to eq(:none)
      end

      it "UNAVAILABLE when no chat-capable provider is configured" do
        stub_usable([])
        p = described_class.select_confidence_panel
        expect(p[:mode]).to eq(:unavailable)
      end

      it "marks the panel sequential when a single-local-server (ollama) is included" do
        stub_usable([{ provider: "openai", model: "a" }, { provider: "ollama", model: "b" }])
        expect(described_class.select_confidence_panel[:sequential]).to be true
      end
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

    it "charges the reserved output for hidden-reasoning models, not the visible text" do
      # gpt-5.5 etc. spend hidden reasoning tokens absent from the text; the budget
      # must fail closed by charging the reserved max_output, not the short reply.
      allow(described_class).to receive(:hidden_reasoning_capable?).and_return(true)
      allow(host).to receive(:send_query).and_return("42")
      result = described_class.call("monadic_query", { "provider" => "openai", "message" => "Hi" })
      expect(result[:budget][:tokens_spent]).to be >= 4096 # DEFAULT_MAX_OUTPUT reserved
    end

    it "charges only the visible-text estimate for non-reasoning models" do
      allow(described_class).to receive(:hidden_reasoning_capable?).and_return(false)
      allow(host).to receive(:send_query).and_return("42")
      result = described_class.call("monadic_query", { "provider" => "openai", "message" => "Hi" })
      expect(result[:budget][:tokens_spent]).to be < 100 # input + tiny visible output
    end

    it "classifies responses-API / thinking models as hidden-reasoning-capable" do
      expect(described_class.send(:hidden_reasoning_capable?, "gpt-5.5")).to be true       # responses API
      expect(described_class.send(:hidden_reasoning_capable?, "claude-sonnet-4-6")).to be true # thinking
      expect(described_class.send(:hidden_reasoning_capable?, "no-such-model-xyz")).to be false # rescue path
    end

    it "flags a possibly-truncated answer (no sentence-final punctuation)" do
      allow(host).to receive(:send_query).and_return("This answer is cut off mid")
      result = described_class.call("monadic_query", { "provider" => "openai", "message" => "hi" })
      expect(result[:possibly_incomplete]).to be true
    end

    it "does not flag a complete answer" do
      allow(host).to receive(:send_query).and_return("This answer is complete.")
      result = described_class.call("monadic_query", { "provider" => "openai", "message" => "hi" })
      expect(result).not_to have_key(:possibly_incomplete)
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

    it "returns a fresh host instance per call (no shared mutable host across threads)" do
      a = described_class.provider_host("anthropic")
      b = described_class.provider_host("anthropic")
      expect(a).not_to be(b)
      expect(a).to respond_to(:send_query)
      expect(b).to respond_to(:send_query)
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

    it "accepts an explicit targets list, including same-provider duplicates, indexed" do
      captured = []
      allow(described_class).to receive(:execute_query) do |provider:, model:, **_|
        captured << [provider, model]
        { provider: provider, model: model, success: true, text: "ok" }
      end
      result = described_class.call("monadic_parallel_query", {
        "targets" => [
          { "provider" => "openai", "model" => "gpt-5.5" },
          { "provider" => "openai", "model" => "gpt-5.4" },
          { "provider" => "anthropic", "model" => "claude-opus-4-8" }
        ],
        "message" => "compare"
      })
      expect(captured).to contain_exactly(
        ["openai", "gpt-5.5"], ["openai", "gpt-5.4"], ["anthropic", "claude-opus-4-8"]
      )
      expect(result[:results].map { |r| r[:index] }).to eq([0, 1, 2])
      expect(result[:results]).to all(include(success: true))
    end

    it "canonicalizes target providers (claude -> anthropic)" do
      captured = []
      allow(described_class).to receive(:execute_query) do |provider:, **_|
        captured << provider
        { provider: provider, success: true }
      end
      described_class.call("monadic_parallel_query", {
        "targets" => [{ "provider" => "claude" }, { "provider" => "openai" }],
        "message" => "hi"
      })
      expect(captured).to contain_exactly("anthropic", "openai")
    end

    it "rejects too many or malformed targets" do
      cap = described_class::MAX_PARALLEL_TARGETS
      many = Array.new(cap + 1) { { "provider" => "openai" } }
      expect { described_class.call("monadic_parallel_query", { "targets" => many, "message" => "hi" }) }
        .to raise_error(ArgumentError, /2-#{cap}/)
      expect { described_class.call("monadic_parallel_query", { "targets" => [{}, {}], "message" => "hi" }) }
        .to raise_error(ArgumentError, /provider/)
    end

    it "requires either targets or providers" do
      expect { described_class.call("monadic_parallel_query", { "message" => "hi" }) }
        .to raise_error(ArgumentError, /providers/)
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

  describe "monadic_analyze_image" do
    let(:vhost) { double("vision_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:agent_host).and_return(vhost)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "returns the analysis text and charges the budget" do
      expect(vhost).to receive(:image_analysis_agent)
        .with(message: "describe", image_path: "pic.png")
        .and_return("A red square on white.")
      result = described_class.call("monadic_analyze_image", {
        "prompt" => "describe", "path" => "pic.png"
      })
      expect(result[:success]).to be true
      expect(result[:text]).to eq("A red square on white.")
      expect(result[:provider]).to eq("auto")
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "passes a requested provider through (canonicalized)" do
      expect(described_class).to receive(:agent_host)
        .with(ImageAnalysisAgent, "anthropic").and_return(vhost)
      allow(vhost).to receive(:image_analysis_agent).and_return("ok")
      described_class.call("monadic_analyze_image", {
        "prompt" => "p", "path" => "x.png", "provider" => "claude"
      })
    end

    it "maps an agent ERROR string to a structured failure" do
      allow(vhost).to receive(:image_analysis_agent)
        .and_return("ERROR: Image file not found: x.png")
      result = described_class.call("monadic_analyze_image", { "prompt" => "p", "path" => "x.png" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Image file not found/)
    end

    it "requires prompt and path" do
      expect { described_class.call("monadic_analyze_image", { "path" => "x.png" }) }
        .to raise_error(ArgumentError, /prompt is required/)
      expect { described_class.call("monadic_analyze_image", { "prompt" => "p" }) }
        .to raise_error(ArgumentError, /path is required/)
    end

    it "refuses when the budget is exhausted (no agent call)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(vhost).not_to receive(:image_analysis_agent)
      result = described_class.call("monadic_analyze_image", { "prompt" => "p", "path" => "x.png" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_transcribe_audio" do
    let(:ahost) { double("audio_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:agent_host).and_return(ahost)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "returns the transcript and charges the budget" do
      expect(ahost).to receive(:audio_transcription_agent)
        .with(hash_including(audio_path: "speech.mp3"))
        .and_return("hello world")
      result = described_class.call("monadic_transcribe_audio", { "path" => "speech.mp3" })
      expect(result[:success]).to be true
      expect(result[:text]).to eq("hello world")
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "maps an agent ERROR string to a structured failure" do
      allow(ahost).to receive(:audio_transcription_agent)
        .and_return("ERROR: Audio file not found: speech.mp3")
      result = described_class.call("monadic_transcribe_audio", { "path" => "speech.mp3" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Audio file not found/)
    end

    it "requires path" do
      expect { described_class.call("monadic_transcribe_audio", {}) }
        .to raise_error(ArgumentError, /path is required/)
    end
  end

  describe "monadic_analyze_audio" do
    before { Monadic::MCP::CostGuard.reset! }
    after { Monadic::MCP::CostGuard.reset! }

    it "analyzes audio with Gemini and charges the budget" do
      allow(described_class).to receive(:resolve_shared_path).with("song.mp3").and_return("/data/song.mp3")
      allow(described_class).to receive(:audio_analyze_model).and_return("gemini-3.5-flash")
      expect(AudioAnalysisAgent).to receive(:analyze)
        .with(audio_path: "/data/song.mp3", prompt: "critique", model: "gemini-3.5-flash")
        .and_return("A lively swing performance.")
      result = described_class.call("monadic_analyze_audio", { "prompt" => "critique", "path" => "song.mp3" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("gemini")
      expect(result[:text]).to eq("A lively swing performance.")
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "maps an ERROR string to a structured failure" do
      allow(described_class).to receive(:resolve_shared_path).and_return("/data/x.mp3")
      allow(described_class).to receive(:audio_analyze_model).and_return("gemini-3.5-flash")
      allow(AudioAnalysisAgent).to receive(:analyze).and_return("ERROR: Audio file not found: x.mp3")
      result = described_class.call("monadic_analyze_audio", { "prompt" => "p", "path" => "x.mp3" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Audio file not found/)
    end

    it "requires prompt and path" do
      expect { described_class.call("monadic_analyze_audio", { "path" => "x.mp3" }) }
        .to raise_error(ArgumentError, /prompt is required/)
      expect { described_class.call("monadic_analyze_audio", { "prompt" => "p" }) }
        .to raise_error(ArgumentError, /path is required/)
    end

    it "rejects a path-traversal path" do
      expect { described_class.call("monadic_analyze_audio", { "prompt" => "p", "path" => "../etc/passwd" }) }
        .to raise_error(ArgumentError, /traversal/)
    end

    it "rejects an absolute path outside the shared volume" do
      expect { described_class.call("monadic_analyze_audio", { "prompt" => "p", "path" => "/etc/passwd" }) }
        .to raise_error(ArgumentError, /within the shared volume/)
    end
  end

  describe "monadic_analyze_video" do
    let(:vhost) { double("video_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      # Simulate running inside a background job (the guard requires it).
      allow(described_class).to receive(:require_background_job).and_return(nil)
      allow(described_class).to receive(:video_analyze_host).and_return(vhost)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "refuses a direct (non-job) call and points to monadic_submit" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_analyze_video", { "path" => "c.mp4" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "analyzes a video and charges the budget" do
      expect(vhost).to receive(:analyze_video)
        .with(file: "clip.mp4", fps: 1, query: "what happens?")
        .and_return("A person waves at the camera.")
      result = described_class.call("monadic_analyze_video",
                                    { "path" => "clip.mp4", "query" => "what happens?" })
      expect(result[:success]).to be true
      expect(result[:text]).to eq("A person waves at the camera.")
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "passes a custom fps and maps an Error string to failure" do
      expect(vhost).to receive(:analyze_video)
        .with(hash_including(fps: 2))
        .and_return("Error: Failed to extract frames from video.")
      result = described_class.call("monadic_analyze_video", { "path" => "c.mp4", "fps" => 2 })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Failed to extract frames/)
    end

    it "requires path" do
      expect { described_class.call("monadic_analyze_video", {}) }
        .to raise_error(ArgumentError, /path is required/)
    end

    it "refuses when the budget is exhausted (no analysis)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(vhost).not_to receive(:analyze_video)
      result = described_class.call("monadic_analyze_video", { "path" => "c.mp4" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_speak" do
    let(:thost) { double("tts_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:tts_host).and_return(thost)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "synthesizes speech and returns the saved filename" do
      expect(thost).to receive(:text_to_speech)
        .with(hash_including(provider: "openai", text: "hello", voice_id: "alloy"))
        .and_return("Command has been executed with the following output: \nText-to-speech audio MP3 saved to 1718967890.mp3")
      result = described_class.call("monadic_speak", { "text" => "hello" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("openai")
      expect(result[:file]).to eq("1718967890.mp3")
      expect(result[:note]).to match(%r{~/monadic/data/1718967890\.mp3})
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "normalizes provider aliases and applies the per-provider default voice" do
      expect(thost).to receive(:text_to_speech)
        .with(hash_including(provider: "gemini", voice_id: "zephyr"))
        .and_return("Text-to-speech audio saved to 42.wav (WAV format)")
      result = described_class.call("monadic_speak", { "text" => "hi", "provider" => "google" })
      expect(result[:provider]).to eq("gemini")
      expect(result[:file]).to eq("42.wav")
    end

    it "passes an explicit voice and speed through" do
      expect(thost).to receive(:text_to_speech)
        .with(hash_including(provider: "elevenlabs", voice_id: "abc123", speed: 1.5))
        .and_return("Text-to-speech audio MP3 saved to v.mp3")
      described_class.call("monadic_speak", {
        "text" => "hi", "provider" => "elevenlabs", "voice" => "abc123", "speed" => 1.5
      })
    end

    it "maps a helper error to a structured failure" do
      allow(thost).to receive(:text_to_speech)
        .and_return("Error occurred: ELEVENLABS_API_KEY is not set.")
      result = described_class.call("monadic_speak", { "text" => "hi", "provider" => "elevenlabs" })
      expect(result[:success]).to be false
      expect(result[:file]).to be_nil
      expect(result[:error]).to match(/ELEVENLABS_API_KEY is not set/)
    end

    it "requires text" do
      expect { described_class.call("monadic_speak", {}) }
        .to raise_error(ArgumentError, /text is required/)
      expect { described_class.call("monadic_speak", { "text" => "   " }) }
        .to raise_error(ArgumentError, /text is required/)
    end

    it "refuses when the budget is exhausted (no synthesis)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(thost).not_to receive(:text_to_speech)
      result = described_class.call("monadic_speak", { "text" => "a long sentence to speak" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_generate_code" do
    let(:chost) { double("code_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:require_background_job).and_return(nil)
      allow(described_class).to receive(:code_provider_configured?).and_return(true)
      allow(described_class).to receive(:code_host).and_return(chost)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "refuses a direct (non-job) call and points to monadic_submit" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_generate_code", { "prompt" => "p" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "generates code with the auto-selected provider and charges the budget" do
      expect(chost).to receive(:call_openai_code).with(prompt: "make a fib fn")
        .and_return({ code: "def fib(n); end", success: true, model: "gpt-5-codex" })
      result = described_class.call("monadic_generate_code", { "prompt" => "make a fib fn" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("openai")
      expect(result[:code]).to include("def fib")
      expect(result[:model]).to eq("gpt-5-codex")
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "routes a requested provider (claude -> anthropic, call_claude_code)" do
      expect(described_class).to receive(:code_host)
        .with("anthropic", "Monadic::Agents::ClaudeCodeAgent").and_return(chost)
      allow(chost).to receive(:call_claude_code).and_return({ code: "x", success: true })
      result = described_class.call("monadic_generate_code", { "prompt" => "p", "provider" => "claude" })
      expect(result[:provider]).to eq("anthropic")
      expect(result[:success]).to be true
    end

    it "maps an agent failure to a structured error" do
      allow(chost).to receive(:call_openai_code)
        .and_return({ error: "OpenAIHelper not available", success: false })
      result = described_class.call("monadic_generate_code", { "prompt" => "p" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/OpenAIHelper not available/)
    end

    it "treats a provider error string leaked into the code field as a failure" do
      allow(chost).to receive(:call_openai_code)
        .and_return({ code: "[OpenAI] API Error: boom", success: true })
      result = described_class.call("monadic_generate_code", { "prompt" => "p" })
      expect(result[:success]).to be false
      expect(result[:code]).to be_nil
      expect(result[:error]).to match(/API Error: boom/)
    end

    it "requires a prompt" do
      expect { described_class.call("monadic_generate_code", {}) }
        .to raise_error(ArgumentError, /prompt is required/)
    end

    it "rejects a provider that has no code agent" do
      expect { described_class.call("monadic_generate_code", { "prompt" => "p", "provider" => "gemini" }) }
        .to raise_error(ArgumentError, /has no code agent/)
    end

    it "reports when no code provider is configured" do
      allow(described_class).to receive(:code_provider_configured?).and_return(false)
      result = described_class.call("monadic_generate_code", { "prompt" => "p" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/No code-capable provider/)
    end

    it "refuses when the budget is exhausted (no agent call)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(chost).not_to receive(:call_openai_code)
      result = described_class.call("monadic_generate_code", { "prompt" => "make something big" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_generate_image" do
    let(:mhost) { double("media_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:require_background_job).and_return(nil)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "refuses a direct (non-job) call and points to monadic_submit" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_generate_image", { "prompt" => "a cat" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "generates with openai and parses 'Saved file' output" do
      allow(described_class).to receive(:media_app_host).and_return(mhost)
      allow(Monadic::Utils::ModelSpec).to receive(:default_image_model).with("openai").and_return("gpt-image-2")
      expect(mhost).to receive(:generate_image_with_openai)
        .with(hash_including(operation: "generate", model: "gpt-image-2", prompt: "a cat"))
        .and_return("output: \nSaved file: /monadic/data/generate_gpt-image-2_123_0.png")
      result = described_class.call("monadic_generate_image", { "prompt" => "a cat" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("openai")
      expect(result[:files]).to eq(["generate_gpt-image-2_123_0.png"])
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "parses a grok JSON result and accepts the xai alias" do
      allow(described_class).to receive(:media_app_host).and_return(mhost)
      expect(mhost).to receive(:generate_image_with_grok)
        .with(hash_including(prompt: "fox", operation: "generate"))
        .and_return(JSON.generate({ success: true, filename: "123.png", revised_prompt: "a fox" }))
      result = described_class.call("monadic_generate_image", { "prompt" => "fox", "provider" => "xai" })
      expect(result[:provider]).to eq("grok")
      expect(result[:files]).to eq(["123.png"])
    end

    it "routes gemini through the gemini helper host (google alias)" do
      ghost = double("gemini_host")
      expect(described_class).to receive(:gemini_media_host).and_return(ghost)
      expect(ghost).to receive(:generate_image_with_gemini)
        .and_return(JSON.generate({ success: true, filename: "g.png", model: "gemini" }))
      result = described_class.call("monadic_generate_image", { "prompt" => "p", "provider" => "google" })
      expect(result[:provider]).to eq("gemini")
      expect(result[:files]).to eq(["g.png"])
    end

    it "maps a failed JSON result to a structured error" do
      allow(described_class).to receive(:media_app_host).and_return(mhost)
      allow(mhost).to receive(:generate_image_with_grok)
        .and_return(JSON.generate({ success: false, message: "content filtered" }))
      result = described_class.call("monadic_generate_image", { "prompt" => "x", "provider" => "grok" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/content filtered/)
    end

    it "maps an openai error output to failure" do
      allow(described_class).to receive(:media_app_host).and_return(mhost)
      allow(Monadic::Utils::ModelSpec).to receive(:default_image_model).and_return("gpt-image-2")
      allow(mhost).to receive(:generate_image_with_openai).and_return("Error occurred: boom")
      result = described_class.call("monadic_generate_image", { "prompt" => "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/boom/)
    end

    it "requires a prompt" do
      expect { described_class.call("monadic_generate_image", {}) }
        .to raise_error(ArgumentError, /prompt is required/)
    end

    it "refuses when the budget is exhausted (no generation)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(described_class).not_to receive(:invoke_image_generator)
      result = described_class.call("monadic_generate_image", { "prompt" => "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_generate_video" do
    let(:mhost) { double("media_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:require_background_job).and_return(nil)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "refuses a direct (non-job) call and points to monadic_submit" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_generate_video", { "prompt" => "waves" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "defaults to Veo (gemini) and parses the JSON filename" do
      ghost = double("gemini_host")
      expect(described_class).to receive(:gemini_media_host).and_return(ghost)
      expect(ghost).to receive(:generate_video_with_veo)
        .with(hash_including(prompt: "a sunrise"))
        .and_return(JSON.generate({ "success" => true, "filename" => "v.mp4" }))
      result = described_class.call("monadic_generate_video", { "prompt" => "a sunrise" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("gemini")
      expect(result[:files]).to eq(["v.mp4"])
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "extracts the JSON + nested filename from Veo's wrapped send_command output" do
      ghost = double("gemini_host")
      allow(described_class).to receive(:gemini_media_host).and_return(ghost)
      wrapped = "Command has been executed with the following output: \n" \
                "Generating video...\nUsing parameters: {\"number_of_videos\" => 1}\n" \
                "{\"success\":true,\"videos\":[{\"filename\":\"v.mp4\",\"aspect_ratio\":\"16:9\"}]}\n"
      allow(ghost).to receive(:generate_video_with_veo).and_return(wrapped)
      result = described_class.call("monadic_generate_video", { "prompt" => "waves" })
      expect(result[:success]).to be true
      expect(result[:files]).to eq(["v.mp4"])
    end

    it "routes grok (xai) image-to-video with the source image path" do
      allow(described_class).to receive(:media_app_host).and_return(mhost)
      expect(mhost).to receive(:generate_video_with_grok_imagine)
        .with(hash_including(prompt: "pan", image_path: "src.png"))
        .and_return(JSON.generate({ success: true, filename: "g.mp4", request_id: "r1" }))
      result = described_class.call("monadic_generate_video",
                                    { "prompt" => "pan", "provider" => "xai", "image_path" => "src.png" })
      expect(result[:provider]).to eq("grok")
      expect(result[:files]).to eq(["g.mp4"])
    end

    it "maps a failed result to a structured error" do
      ghost = double("gemini_host")
      allow(described_class).to receive(:gemini_media_host).and_return(ghost)
      allow(ghost).to receive(:generate_video_with_veo)
        .and_return(JSON.generate({ "success" => false, "message" => "blocked" }))
      result = described_class.call("monadic_generate_video", { "prompt" => "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/blocked/)
    end

    it "requires a prompt" do
      expect { described_class.call("monadic_generate_video", {}) }
        .to raise_error(ArgumentError, /prompt is required/)
    end

    it "refuses when the budget is exhausted (no generation)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(described_class).not_to receive(:invoke_video_generator)
      result = described_class.call("monadic_generate_video", { "prompt" => "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "monadic_generate_music" do
    let(:ghost) { double("gemini_host") }

    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:require_background_job).and_return(nil)
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "refuses a direct (non-job) call and points to monadic_submit" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_generate_music", { "prompt" => "jazz" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "generates with Lyria and returns the saved filename" do
      allow(described_class).to receive(:gemini_media_host).and_return(ghost)
      expect(ghost).to receive(:generate_music_with_lyria)
        .with(hash_including(prompt: "lofi beat"))
        .and_return(JSON.generate({ success: true, filename: "lyria_1.mp3", mime_type: "audio/mp3" }))
      result = described_class.call("monadic_generate_music", { "prompt" => "lofi beat" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("gemini")
      expect(result[:files]).to eq(["lyria_1.mp3"])
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "passes an explicit output format through" do
      allow(described_class).to receive(:gemini_media_host).and_return(ghost)
      expect(ghost).to receive(:generate_music_with_lyria)
        .with(hash_including(prompt: "jazz", output_format: "wav"))
        .and_return(JSON.generate({ success: true, filename: "j.wav" }))
      described_class.call("monadic_generate_music", { "prompt" => "jazz", "format" => "wav" })
    end

    it "maps a failed result to a structured error" do
      allow(described_class).to receive(:gemini_media_host).and_return(ghost)
      allow(ghost).to receive(:generate_music_with_lyria)
        .and_return(JSON.generate({ success: false, error: "filtered" }))
      result = described_class.call("monadic_generate_music", { "prompt" => "x" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/filtered/)
    end

    it "requires a prompt" do
      expect { described_class.call("monadic_generate_music", {}) }
        .to raise_error(ArgumentError, /prompt is required/)
    end
  end

  describe "monadic_agent" do
    before do
      Monadic::MCP::CostGuard.reset!
      allow(described_class).to receive(:require_background_job).and_return(nil)
      allow(described_class).to receive(:default_chat_model_for).and_return("gpt-x")
    end

    after { Monadic::MCP::CostGuard.reset! }

    it "runs the bounded agent and returns its final answer" do
      expect(Monadic::MCP::ConduitAgent).to receive(:run)
        .with(hash_including(task: "find X", provider: "openai", model: "gpt-x"))
        .and_return("Here is what I found about X. (https://example.com)")
      result = described_class.call("monadic_agent", { "task" => "find X" })
      expect(result[:success]).to be true
      expect(result[:provider]).to eq("openai")
      expect(result[:tools]).to eq(["web_search_tools"])
      expect(result[:text]).to match(/found about X/)
      expect(result[:budget][:tokens_spent]).to be > 0
    end

    it "passes requested tool groups and provider (claude -> anthropic)" do
      expect(Monadic::MCP::ConduitAgent).to receive(:run)
        .with(hash_including(provider: "anthropic", groups: %w[web_search_tools file_reading]))
        .and_return("ok.")
      described_class.call("monadic_agent",
                           { "task" => "t", "provider" => "claude",
                             "tools" => %w[web_search_tools file_reading] })
    end

    it "surfaces an agent error as failure" do
      allow(Monadic::MCP::ConduitAgent).to receive(:run).and_return("ERROR: no web search key")
      result = described_class.call("monadic_agent", { "task" => "t" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/no web search key/)
    end

    it "requires a task" do
      expect { described_class.call("monadic_agent", {}) }
        .to raise_error(ArgumentError, /task is required/)
    end

    it "refuses a direct (non-job) call" do
      allow(described_class).to receive(:require_background_job).and_call_original
      result = described_class.call("monadic_agent", { "task" => "t" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/must run in the background/)
    end

    it "refuses when the budget is exhausted (no agent run)" do
      stub_const("CONFIG", CONFIG.merge("CONDUIT_TOKEN_BUDGET" => "1"))
      expect(Monadic::MCP::ConduitAgent).not_to receive(:run)
      result = described_class.call("monadic_agent", { "task" => "t" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Budget exceeded/)
    end
  end

  describe "background jobs (submit/poll/cancel/jobs)" do
    after { Monadic::MCP::JobStore.reset! }

    it "submits a tool and runs it to completion off the reactor" do
      result = described_class.call("monadic_submit",
                                    { "tool" => "monadic_status", "arguments" => {} })
      expect(result[:success]).to be true
      expect(result[:tool]).to eq("monadic_status")
      expect(result[:status]).to eq("running")

      id = result[:job_id]
      # Deterministic wait: join the worker thread instead of sleeping.
      Monadic::MCP::JobStore.fetch(id).thread.join

      polled = described_class.call("monadic_poll", { "job_id" => id })
      expect(polled[:status]).to eq("done")
      expect(polled[:result]).to include(:backend)
    end

    it "captures a tool error as a failed job" do
      # second_opinion raises ArgumentError without a query.
      result = described_class.call("monadic_submit",
                                    { "tool" => "monadic_second_opinion", "arguments" => {} })
      Monadic::MCP::JobStore.fetch(result[:job_id]).thread.join
      polled = described_class.call("monadic_poll", { "job_id" => result[:job_id] })
      expect(polled[:status]).to eq("error")
      expect(polled[:error]).to be_a(String)
    end

    it "rejects unknown and job-control tools" do
      expect { described_class.call("monadic_submit", { "tool" => "nope" }) }
        .to raise_error(ArgumentError, /unknown tool/)
      expect { described_class.call("monadic_submit", { "tool" => "monadic_poll" }) }
        .to raise_error(ArgumentError, /cannot be run as a background job/)
      expect { described_class.call("monadic_submit", {}) }
        .to raise_error(ArgumentError, /tool is required/)
    end

    it "enforces the concurrency cap" do
      gate = Queue.new
      # Stub the dispatched tool to block until released so jobs stay running.
      allow(described_class).to receive(:handle_status) { gate.pop }

      cap = Monadic::MCP::JobStore::MAX_CONCURRENT
      ids = Array.new(cap) do
        described_class.call("monadic_submit", { "tool" => "monadic_status" })[:job_id]
      end

      over = described_class.call("monadic_submit", { "tool" => "monadic_status" })
      expect(over[:success]).to be false
      expect(over[:error]).to match(/Too many concurrent jobs/)

      cap.times { gate.push(:go) }
      ids.each { |id| Monadic::MCP::JobStore.fetch(id).thread.join }
    end

    it "cancels a running job" do
      gate = Queue.new
      allow(described_class).to receive(:handle_status) { gate.pop }

      id = described_class.call("monadic_submit", { "tool" => "monadic_status" })[:job_id]
      cancelled = described_class.call("monadic_cancel", { "job_id" => id })
      expect(cancelled[:status]).to eq("cancelled")

      missing = described_class.call("monadic_cancel", { "job_id" => "does-not-exist" })
      expect(missing[:success]).to be false
    end

    it "lists jobs and reports an unknown poll" do
      described_class.call("monadic_submit", { "tool" => "monadic_status" })
      listing = described_class.call("monadic_jobs", {})
      expect(listing[:jobs]).to be_an(Array)
      expect(listing[:jobs].first).to include(:job_id, :tool, :status)

      poll = described_class.call("monadic_poll", { "job_id" => "missing" })
      expect(poll[:success]).to be false
      expect(poll[:error]).to match(/Unknown or expired job/)
    end

    it "surfaces a job's progress snapshot through poll while it runs" do
      reported = Queue.new
      gate = Queue.new
      allow(described_class).to receive(:handle_status) do
        Monadic::MCP::JobStore.report(Monadic::MCP::JobStore.current_job_id, "checking containers")
        reported.push(:ok)
        gate.pop
        { ok: true }
      end

      id = described_class.call("monadic_submit", { "tool" => "monadic_status" })[:job_id]
      reported.pop # progress recorded

      polled = described_class.call("monadic_poll", { "job_id" => id })
      expect(polled[:status]).to eq("running")
      expect(polled[:progress]).to eq("checking containers")
      expect(polled[:progress_at]).to be_a(String)

      gate.push(:go)
      Monadic::MCP::JobStore.fetch(id).thread.join
    end
  end

  describe "progress fragment rendering" do
    it "renders a sequential step fragment as content (n/total)" do
      msg = described_class.send(:progress_message,
                                 { "content" => "Generating code",
                                   "step_progress" => { "current" => 1, "total" => 4 } })
      expect(msg).to eq("Generating code (2/4)")
    end

    it "passes a plain content fragment through" do
      expect(described_class.send(:progress_message, { "content" => "Working" })).to eq("Working")
    end

    it "has no progress reporter outside a background job" do
      expect(described_class.send(:job_progress_reporter)).to be_nil
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
