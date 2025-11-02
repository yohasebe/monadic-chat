# frozen_string_literal: true

require_relative "../../../lib/monadic/utils/badge_builder"

RSpec.describe Monadic::Utils::BadgeBuilder do
  describe ".build_all_badges" do
    it "returns a hash with tools and capabilities keys" do
      result = described_class.build_all_badges({})

      expect(result).to be_a(Hash)
      expect(result).to have_key(:tools)
      expect(result).to have_key(:capabilities)
      expect(result[:tools]).to be_an(Array)
      expect(result[:capabilities]).to be_an(Array)
    end

    it "handles exceptions gracefully" do
      # Pass invalid input that might raise errors
      result = described_class.build_all_badges(nil)

      expect(result).to eq({ tools: [], capabilities: [] })
    end
  end

  describe ".build_tool_badges" do
    context "with imported_tool_groups" do
      it "builds tool badges from imported_tool_groups" do
        settings = {
          imported_tool_groups: [
            { name: :file_operations, visibility: "always", tool_count: 3 }
          ]
        }

        result = described_class.build_all_badges(settings)

        expect(result[:tools].size).to eq(1)
        expect(result[:tools][0][:type]).to eq(:tools)
        expect(result[:tools][0][:subtype]).to eq(:group)
        expect(result[:tools][0][:label]).to eq("file operations")
        expect(result[:tools][0][:icon]).to eq("fa-folder")
        expect(result[:tools][0][:visibility]).to eq("always")
      end

      it "uses fallback icon for unmapped tool groups" do
        settings = {
          imported_tool_groups: [
            { name: :unknown_group, visibility: "always", tool_count: 1 }
          ]
        }

        result = described_class.build_all_badges(settings)

        expect(result[:tools][0][:icon]).to eq("fa-tools")
      end
    end

    context "with tools data in OpenAI/Claude Hash format" do
      it "extracts agent tools from Hash format" do
        settings = {
          tools: {
            tools: [
              { name: "openai_code_agent", description: "Code generation", visibility: "conditional" }
            ]
          }
        }

        result = described_class.build_all_badges(settings)

        agent_badge = result[:tools].find { |b| b[:subtype] == :agent }
        expect(agent_badge).not_to be_nil
        expect(agent_badge[:label]).to eq("code agent")
        expect(agent_badge[:icon]).to eq("fa-robot")
        expect(agent_badge[:visibility]).to eq("conditional")
      end

      it "handles tools with string keys" do
        settings = {
          tools: {
            "tools" => [
              { "name" => "grok_code_agent", "description" => "Code agent" }
            ]
          }
        }

        result = described_class.build_all_badges(settings)

        agent_badge = result[:tools].find { |b| b[:subtype] == :agent }
        expect(agent_badge).not_to be_nil
        expect(agent_badge[:label]).to eq("code agent")
      end
    end

    context "with tools data in Gemini Array format" do
      it "extracts agent tools from Array format with generic labels" do
        settings = {
          tools: [
            { name: "openai_code_agent", description: "Code generation agent" }
          ]
        }

        result = described_class.build_all_badges(settings)

        expect(result[:tools]).to be_an(Array)
        agent_badge = result[:tools].find { |b| b[:subtype] == :agent }
        expect(agent_badge).not_to be_nil
        expect(agent_badge[:label]).to eq("code agent")
        expect(agent_badge[:id]).to eq("openai_code_agent")
      end

      it "does not crash with non-agent tools in Array format" do
        settings = {
          tools: [
            { name: "regular_tool", description: "Not an agent" }
          ]
        }

        result = described_class.build_all_badges(settings)

        # Should not include non-agent tools
        agent_badges = result[:tools].select { |b| b[:subtype] == :agent }
        expect(agent_badges).to be_empty
      end
    end

    context "with nil tools" do
      it "handles nil tools gracefully" do
        settings = { tools: nil }

        result = described_class.build_all_badges(settings)

        expect(result[:tools]).to eq([])
      end
    end

    context "with empty Hash tools" do
      it "handles empty Hash gracefully" do
        settings = { tools: {} }

        result = described_class.build_all_badges(settings)

        expect(result[:tools]).to eq([])
      end
    end

    context "with malformed tools data" do
      it "handles non-Hash, non-Array tools gracefully" do
        settings = { tools: "invalid" }

        result = described_class.build_all_badges(settings)

        expect(result[:tools]).to eq([])
      end

      it "skips non-Hash items in tools array" do
        settings = {
          tools: [
            "not a hash",
            { name: "openai_code_agent" },
            nil
          ]
        }

        result = described_class.build_all_badges(settings)

        # Should only extract the valid agent tool
        agent_badges = result[:tools].select { |b| b[:subtype] == :agent }
        expect(agent_badges.size).to eq(1)
      end

      it "skips tools without name" do
        settings = {
          tools: {
            tools: [
              { description: "No name" },
              { name: "openai_code_agent" }
            ]
          }
        }

        result = described_class.build_all_badges(settings)

        agent_badges = result[:tools].select { |b| b[:subtype] == :agent }
        expect(agent_badges.size).to eq(1)
      end
    end
  end

  describe ".build_capability_badges" do
    context "with features" do
      it "builds capability badges from features" do
        settings = {
          features: { monadic: true, mathjax: true }
        }

        result = described_class.build_all_badges(settings)

        expect(result[:capabilities].size).to eq(2)
        expect(result[:capabilities].map { |b| b[:id] }).to contain_exactly("monadic", "mathjax")
      end

      it "marks user-controlled features correctly" do
        settings = {
          features: { mathjax: true, monadic: true }
        }

        result = described_class.build_all_badges(settings)

        mathjax_badge = result[:capabilities].find { |b| b[:id] == "mathjax" }
        monadic_badge = result[:capabilities].find { |b| b[:id] == "monadic" }

        expect(mathjax_badge[:user_controlled]).to be true
        expect(monadic_badge[:user_controlled]).to be false
      end

      it "filters out features not in BADGE_WORTHY_FEATURES" do
        settings = {
          features: { monadic: true, internal_flag: true }
        }

        result = described_class.build_all_badges(settings)

        # Only monadic should be included
        expect(result[:capabilities].map { |b| b[:id] }).to contain_exactly("monadic")
      end
    end

    context "with agents configuration" do
      it "reads agent configuration from settings[:agents] not [:llm_agents]" do
        settings = {
          agents: { code_generator: "gpt-5-codex" }
        }

        result = described_class.build_all_badges(settings)

        backend_badges = result[:capabilities].select { |b| b[:subtype] == :backend }
        expect(backend_badges.size).to eq(1)
        expect(backend_badges[0][:label]).to eq("gpt-5-codex")
      end

      it "includes backend models from agents block" do
        settings = {
          agents: {
            code_generator: "gpt-5-codex",
            speech_to_text: "whisper-1"
          }
        }

        result = described_class.build_all_badges(settings)

        backend_badges = result[:capabilities].select { |b| b[:subtype] == :backend }
        expect(backend_badges.size).to eq(2)
        expect(backend_badges.map { |b| b[:label] }).to contain_exactly("gpt-5-codex", "whisper-1")
      end

      it "skips nil or empty model names" do
        settings = {
          agents: {
            code_generator: "gpt-5-codex",
            invalid_agent: nil,
            empty_agent: ""
          }
        }

        result = described_class.build_all_badges(settings)

        backend_badges = result[:capabilities].select { |b| b[:subtype] == :backend }
        expect(backend_badges.size).to eq(1)
      end
    end

    context "with both features and agents" do
      it "combines features and backend models" do
        settings = {
          features: { monadic: true, image: true },
          agents: { code_generator: "gpt-5-codex" }
        }

        result = described_class.build_all_badges(settings)

        feature_badges = result[:capabilities].select { |b| b[:subtype] == :feature }
        backend_badges = result[:capabilities].select { |b| b[:subtype] == :backend }

        expect(feature_badges.size).to eq(2)
        expect(backend_badges.size).to eq(1)
      end
    end

    context "with feature name aliases" do
      it "normalizes pdf_vector_storage to pdf" do
        settings = {
          features: { pdf_vector_storage: true }
        }

        result = described_class.build_all_badges(settings)

        pdf_badge = result[:capabilities].find { |b| b[:id] == "pdf" }
        expect(pdf_badge).not_to be_nil
        expect(pdf_badge[:label]).to eq("pdf input")
      end

      it "normalizes pdf_upload to pdf" do
        settings = {
          features: { pdf_upload: true }
        }

        result = described_class.build_all_badges(settings)

        pdf_badge = result[:capabilities].find { |b| b[:id] == "pdf" }
        expect(pdf_badge).not_to be_nil
      end
    end
  end

  describe ".normalize_feature_names" do
    it "preserves original feature names" do
      features = { image: true, websearch: true }
      normalized = described_class.normalize_feature_names(features)

      expect(normalized[:image]).to be true
      expect(normalized[:websearch]).to be true
    end

    it "maps pdf_vector_storage to pdf" do
      features = { pdf_vector_storage: true }
      normalized = described_class.normalize_feature_names(features)

      expect(normalized[:pdf]).to be true
      expect(normalized[:pdf_vector_storage]).to be true # Original preserved
    end

    it "maps pdf_upload to pdf" do
      features = { pdf_upload: true }
      normalized = described_class.normalize_feature_names(features)

      expect(normalized[:pdf]).to be true
    end

    it "handles empty features hash" do
      features = {}
      normalized = described_class.normalize_feature_names(features)

      expect(normalized).to eq({})
    end
  end

  describe ".get_tool_group_icon" do
    it "returns correct icon for known tool groups" do
      expect(described_class.get_tool_group_icon(:file_operations)).to eq("fa-folder")
      expect(described_class.get_tool_group_icon(:python_execution)).to eq("fa-terminal")
      expect(described_class.get_tool_group_icon(:web_search_tools)).to eq("fa-search")
    end

    it "returns fallback icon for unknown tool groups" do
      expect(described_class.get_tool_group_icon(:unknown_group)).to eq("fa-tools")
    end

    it "handles string input" do
      expect(described_class.get_tool_group_icon("file_operations")).to eq("fa-folder")
    end
  end

  describe ".format_label" do
    it "converts snake_case to spaces" do
      expect(described_class.format_label("file_operations")).to eq("file operations")
      expect(described_class.format_label("web_search_tools")).to eq("web search tools")
    end

    it "handles symbols" do
      expect(described_class.format_label(:file_operations)).to eq("file operations")
    end

    it "handles strings without underscores" do
      expect(described_class.format_label("monadic")).to eq("monadic")
    end
  end
end
