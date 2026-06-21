# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/monadic/utils/model_spec"
require_relative "../../../lib/monadic/utils/container_dependencies"
require_relative "../../../lib/monadic/mcp/conduit"

RSpec.describe Monadic::MCP::Conduit do
  describe ".tools" do
    subject(:tools) { described_class.tools }

    it "exposes exactly the Phase 0 capability tools" do
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly("monadic_status", "monadic_list_models")
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
end
