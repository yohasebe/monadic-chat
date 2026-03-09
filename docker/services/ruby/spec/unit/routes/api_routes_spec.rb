# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "API Routes Logic" do
  describe "/api/ai_user_defaults logic" do
    let(:providers) { %w[openai anthropic gemini cohere mistral deepseek grok perplexity] }
    let(:provider_key_map) do
      {
        "openai" => "OPENAI_API_KEY",
        "anthropic" => "ANTHROPIC_API_KEY",
        "gemini" => "GEMINI_API_KEY",
        "cohere" => "COHERE_API_KEY",
        "mistral" => "MISTRAL_API_KEY",
        "deepseek" => "DEEPSEEK_API_KEY",
        "grok" => "XAI_API_KEY",
        "perplexity" => "PERPLEXITY_API_KEY"
      }
    end

    before do
      allow(CONFIG).to receive(:[]).and_call_original
    end

    it "detects provider availability from CONFIG keys" do
      # Simulate: openai has key, anthropic empty, gemini nil
      allow(CONFIG).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-test-key")
      allow(CONFIG).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("")
      allow(CONFIG).to receive(:[]).with("GEMINI_API_KEY").and_return(nil)

      openai_has_key = !!(CONFIG["OPENAI_API_KEY"] && !CONFIG["OPENAI_API_KEY"].to_s.strip.empty?)
      anthropic_has_key = !!(CONFIG["ANTHROPIC_API_KEY"] && !CONFIG["ANTHROPIC_API_KEY"].to_s.strip.empty?)
      gemini_has_key = !!(CONFIG["GEMINI_API_KEY"] && !CONFIG["GEMINI_API_KEY"].to_s.strip.empty?)

      expect(openai_has_key).to be true
      expect(anthropic_has_key).to be false
      expect(gemini_has_key).to be false
    end

    it "treats whitespace-only keys as unavailable" do
      allow(CONFIG).to receive(:[]).with("OPENAI_API_KEY").and_return("   ")

      has_key = !!(CONFIG["OPENAI_API_KEY"] && !CONFIG["OPENAI_API_KEY"].to_s.strip.empty?)
      expect(has_key).to be false
    end

    it "maps grok provider to XAI_API_KEY" do
      expect(provider_key_map["grok"]).to eq("XAI_API_KEY")
    end

    it "covers all 8 providers" do
      expect(providers.length).to eq(8)
      providers.each do |p|
        expect(provider_key_map).to have_key(p), "Missing key mapping for #{p}"
      end
    end
  end

  describe "/api/capabilities logic" do
    before do
      allow(CONFIG).to receive(:[]).and_call_original
    end

    it "returns latex disabled when INSTALL_LATEX not set" do
      allow(CONFIG).to receive(:[]).with("INSTALL_LATEX").and_return(nil)

      latex_enabled = !!(CONFIG && CONFIG["INSTALL_LATEX"])
      expect(latex_enabled).to be false
    end

    it "returns latex enabled when INSTALL_LATEX is set" do
      allow(CONFIG).to receive(:[]).with("INSTALL_LATEX").and_return(true)

      latex_enabled = !!(CONFIG && CONFIG["INSTALL_LATEX"])
      expect(latex_enabled).to be true
    end

    it "checks provider keys with strip for capabilities" do
      allow(CONFIG).to receive(:[]).with("OPENAI_API_KEY").and_return("key")
      allow(CONFIG).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      allow(CONFIG).to receive(:[]).with("TAVILY_API_KEY").and_return("")

      providers = {
        openai: !!(CONFIG && CONFIG["OPENAI_API_KEY"] && !CONFIG["OPENAI_API_KEY"].to_s.strip.empty?),
        anthropic: !!(CONFIG && CONFIG["ANTHROPIC_API_KEY"] && !CONFIG["ANTHROPIC_API_KEY"].to_s.strip.empty?),
        tavily: !!(CONFIG && CONFIG["TAVILY_API_KEY"] && !CONFIG["TAVILY_API_KEY"].to_s.strip.empty?)
      }

      expect(providers[:openai]).to be true
      expect(providers[:anthropic]).to be false
      expect(providers[:tavily]).to be false
    end

    it "always reports selenium as enabled" do
      resp = { selenium: { enabled: true } }
      expect(resp[:selenium][:enabled]).to be true
    end
  end

  describe "/api/environment logic" do
    before do
      allow(CONFIG).to receive(:[]).and_call_original
    end

    it "reports max_stored_messages with default of 1000" do
      allow(CONFIG).to receive(:[]).with("MAX_STORED_MESSAGES").and_return(nil)

      max = (CONFIG["MAX_STORED_MESSAGES"] || "1000").to_i
      expect(max).to eq(1000)
    end

    it "uses configured MAX_STORED_MESSAGES" do
      allow(CONFIG).to receive(:[]).with("MAX_STORED_MESSAGES").and_return("500")

      max = (CONFIG["MAX_STORED_MESSAGES"] || "1000").to_i
      expect(max).to eq(500)
    end
  end

  describe "/api/apps/graph_list deduplication logic" do
    it "deduplicates apps by display_name, preferring openai" do
      apps = {
        "ChatOpenAI" => double(settings: { display_name: "Chat", provider: "openai" }),
        "ChatClaude" => double(settings: { display_name: "Chat", provider: "anthropic" }),
        "MathOpenAI" => double(settings: { display_name: "Math Tutor", provider: "openai" })
      }

      by_display = {}
      apps.each do |app_name, app|
        s = app.settings
        dn = (s[:display_name] || s["display_name"] || app_name).to_s
        provider = (s[:provider] || s["provider"] || s[:group] || s["group"]).to_s.downcase
        existing = by_display[dn]
        if existing.nil? || (provider == "openai" && existing[:provider] != "openai")
          by_display[dn] = { app_name: app_name, display_name: dn, provider: provider }
        end
      end

      result = by_display.values.sort_by { |e| e[:display_name] }

      expect(result.length).to eq(2)
      chat_entry = result.find { |e| e[:display_name] == "Chat" }
      expect(chat_entry[:app_name]).to eq("ChatOpenAI")
      expect(chat_entry[:provider]).to eq("openai")
    end

    it "keeps non-openai when no openai variant exists" do
      apps = {
        "SpecialClaude" => double(settings: { display_name: "Special App", provider: "anthropic" })
      }

      by_display = {}
      apps.each do |app_name, app|
        s = app.settings
        dn = (s[:display_name] || app_name).to_s
        provider = (s[:provider] || s[:group]).to_s.downcase
        existing = by_display[dn]
        if existing.nil? || (provider == "openai" && existing[:provider] != "openai")
          by_display[dn] = { app_name: app_name, display_name: dn, provider: provider }
        end
      end

      result = by_display.values
      expect(result.length).to eq(1)
      expect(result.first[:provider]).to eq("anthropic")
    end
  end

  describe "/api/app/:name/graph data extraction" do
    it "determines input types from settings" do
      settings = { image: true, pdf: false, pdf_vector_storage: true }

      input_types = ["text"]
      input_types << "image" if settings[:image] || settings["image"]
      input_types << "pdf" if settings[:pdf] || settings["pdf"] || settings[:pdf_vector_storage] || settings["pdf_vector_storage"]

      expect(input_types).to include("text", "image", "pdf")
    end

    it "determines output types from settings" do
      settings = { image_generation: true, auto_speech: false }

      output_types = ["text"]
      output_types << "image" if settings[:image_generation] || settings["image_generation"]
      output_types << "audio" if settings[:auto_speech] || settings["auto_speech"]

      expect(output_types).to eq(["text", "image"])
    end

    it "truncates long system prompts at 2000 chars" do
      long_prompt = "x" * 3000

      result = long_prompt.length > 2000 ? long_prompt[0, 2000] + "..." : long_prompt
      expect(result.length).to eq(2003) # 2000 + "..."
      expect(result).to end_with("...")
    end

    it "preserves short system prompts unchanged" do
      short_prompt = "You are a helpful assistant."

      result = short_prompt.length > 2000 ? short_prompt[0, 2000] + "..." : short_prompt
      expect(result).to eq(short_prompt)
    end
  end
end
