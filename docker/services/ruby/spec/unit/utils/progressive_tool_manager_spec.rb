# frozen_string_literal: true

require_relative "../../../lib/monadic/utils/progressive_tool_manager"

RSpec.describe Monadic::Utils::ProgressiveToolManager do
  let(:app_name) { "TestApp" }

  # Two skills: a multi-tool group (web_search_tools -> 4 tools) and a
  # single-tool group (image_analysis -> 1 tool). request_tool is always visible.
  let(:web_tools) { %w[search_web fetch_web_content tavily_search tavily_fetch] }

  let(:web_hint) { 'Call request_tool("web_search_tools") when you need to search the web.' }
  let(:image_hint) { 'Call request_tool("image_analysis") when you need to analyze images.' }

  let(:conditional) do
    web_tools.map do |name|
      {
        name: name,
        description: "#{name} description",
        visibility: :conditional,
        unlock_conditions: [{ tool_request: "web_search_tools" }],
        unlock_hint: web_hint
      }
    end + [
      {
        name: "analyze_image",
        description: "analyze image",
        visibility: :conditional,
        unlock_conditions: [{ tool_request: "image_analysis" }],
        unlock_hint: image_hint
      }
    ]
  end

  let(:all_tool_names) { web_tools + ["analyze_image", "request_tool"] }

  let(:app_settings) do
    {
      "progressive_tools" => {
        provider: :openai,
        all_tool_names: all_tool_names,
        always_visible: ["request_tool"],
        conditional: conditional
      }
    }
  end

  let(:tools) do
    (web_tools + ["analyze_image"]).map do |name|
      { "type" => "function", "function" => { "name" => name, "description" => "#{name} description" } }
    end + [
      { "type" => "function", "function" => { "name" => "request_tool", "description" => "Request access to a locked tool by name" } }
    ]
  end

  let(:session) { {} }

  def visible_names
    described_class.visible_tools(
      app_name: app_name, session: session, app_settings: app_settings, default_tools: tools
    ).map { |t| t["function"]["name"] }
  end

  describe "#visible_tools" do
    it "hides all conditional tools until unlocked, keeping only always-visible ones" do
      expect(visible_names).to eq(["request_tool"])
    end
  end

  describe "#unlock_request" do
    it "unlocks the entire bundle when given a group name" do
      newly = described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      expect(newly).to match_array(web_tools)
      expect(visible_names).to match_array(["request_tool"] + web_tools)
      expect(visible_names).not_to include("analyze_image")
    end

    it "unlocks a single tool when given an individual tool name" do
      newly = described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "analyze_image"
      )
      expect(newly).to eq(["analyze_image"])
      expect(visible_names).to match_array(["request_tool", "analyze_image"])
    end

    it "returns an empty array for an unknown key and for an already-unlocked skill" do
      expect(described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "nope"
      )).to eq([])

      described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      expect(described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )).to eq([])
    end
  end

  describe "#skill_menu" do
    it "lists one hint per still-locked group" do
      lines = described_class.skill_menu(app_settings: app_settings, session: session, app_name: app_name)
      expect(lines).to contain_exactly(web_hint, image_hint)
    end

    it "drops a group from the menu once all its tools are unlocked" do
      described_class.unlock_request(
        session: session, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      lines = described_class.skill_menu(app_settings: app_settings, session: session, app_name: app_name)
      expect(lines).to eq([image_hint])
    end
  end

  describe "#annotate_request_tool" do
    it "injects the skill menu into request_tool's description" do
      annotated = described_class.annotate_request_tool(
        tools: tools, app_settings: app_settings, session: session, app_name: app_name
      )
      request_tool = annotated.find { |t| t["function"]["name"] == "request_tool" }
      expect(request_tool["function"]["description"]).to include("Available skills")
      expect(request_tool["function"]["description"]).to include(web_hint)
      expect(request_tool["function"]["description"]).to include(image_hint)
    end

    it "does not mutate the original tools array (non-destructive)" do
      original = tools.find { |t| t["function"]["name"] == "request_tool" }["function"]["description"].dup
      described_class.annotate_request_tool(
        tools: tools, app_settings: app_settings, session: session, app_name: app_name
      )
      expect(tools.find { |t| t["function"]["name"] == "request_tool" }["function"]["description"]).to eq(original)
    end

    it "leaves tools unchanged when nothing is locked" do
      described_class.unlock_request(session: session, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools")
      described_class.unlock_request(session: session, app_name: app_name, app_settings: app_settings, request_key: "analyze_image")
      annotated = described_class.annotate_request_tool(
        tools: tools, app_settings: app_settings, session: session, app_name: app_name
      )
      expect(annotated).to eq(tools)
    end
  end
end
