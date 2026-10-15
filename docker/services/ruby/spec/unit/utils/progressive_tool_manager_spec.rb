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

    it "prefixes request_tool(...) onto a hint that omits it (422 guard)" do
      bad_settings = {
        "progressive_tools" => {
          provider: :openai,
          all_tool_names: ["notes_search", "request_tool"],
          always_visible: ["request_tool"],
          conditional: [
            {
              name: "notes_search",
              description: "search notes",
              visibility: :conditional,
              unlock_conditions: [{ tool_request: "notes_search" }],
              # Malformed: says "Call notes_search" without routing through request_tool.
              unlock_hint: "Call notes_search when the user references their notes."
            }
          ]
        }
      }
      lines = described_class.skill_menu(app_settings: bad_settings, session: {}, app_name: "BadApp")
      expect(lines.size).to eq(1)
      expect(lines.first).to include('request_tool("notes_search")')
    end
  end

  # The web_search_tools group is governed by the Web Search UI toggle, not by
  # dynamic unlocking. When the toggle is explicitly off it must stay fully
  # hidden: absent from the tool set and menu, and not unlockable.
  describe "Web Search UI-toggle gating" do
    let(:ws_off) { { parameters: { "websearch" => false } } }
    let(:ws_on) { { parameters: { "websearch" => true } } }

    def visible_with(session)
      described_class.visible_tools(
        app_name: app_name, session: session, app_settings: app_settings, default_tools: tools
      ).map { |t| t["function"]["name"] }
    end

    it "refuses to unlock web_search_tools via request_tool while the toggle is off" do
      newly = described_class.unlock_request(
        session: ws_off, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      expect(newly).to eq([])
    end

    it "hides web_search_tools from visible_tools when the toggle is off" do
      expect(visible_with(ws_off)).not_to include(*web_tools)
      expect(visible_with(ws_off)).to include("request_tool")
    end

    it "omits web_search_tools from the skill menu when the toggle is off" do
      lines = described_class.skill_menu(app_settings: app_settings, session: ws_off, app_name: app_name)
      expect(lines.join("\n")).not_to include("web_search_tools")
    end

    it "does not gate other groups (image_analysis) when the toggle is off" do
      newly = described_class.unlock_request(
        session: ws_off, app_name: app_name, app_settings: app_settings, request_key: "image_analysis"
      )
      expect(newly).to eq(["analyze_image"])
    end

    it "allows web_search_tools normally when the toggle is on" do
      newly = described_class.unlock_request(
        session: ws_on, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      expect(newly).to match_array(web_tools)
      expect(visible_with(ws_on)).to include(*web_tools)
    end

    it "does not gate when websearch is absent (headless / not a UI session)" do
      newly = described_class.unlock_request(
        session: {}, app_name: app_name, app_settings: app_settings, request_key: "web_search_tools"
      )
      expect(newly).to match_array(web_tools)
    end
  end

  # The library_search group follows the Knowledge Base toggle: visible without
  # unlocking while it is on, hidden and not unlockable while it is off.
  describe "Knowledge Base toggle gating" do
    let(:kb_settings) do
      {
        "progressive_tools" => {
          provider: :openai,
          all_tool_names: ["library_search", "analyze_image", "request_tool"],
          always_visible: ["request_tool"],
          conditional: [
            { name: "library_search", visibility: :conditional,
              unlock_conditions: [{ tool_request: "library_search" }], unlock_hint: "search the Knowledge Base" },
            { name: "analyze_image", visibility: :conditional,
              unlock_conditions: [{ tool_request: "image_analysis" }], unlock_hint: "analyze images" }
          ]
        }
      }
    end
    let(:kb_tools) do
      %w[library_search analyze_image request_tool].map { |n| { "type" => "function", "function" => { "name" => n } } }
    end
    let(:kb_on) { { parameters: { "library_rag_enabled" => true } } }
    let(:kb_off) { { parameters: { "library_rag_enabled" => false } } }

    def kb_visible(session)
      described_class.visible_tools(
        app_name: "KbApp", session: session, app_settings: kb_settings, default_tools: kb_tools
      ).map { |t| t["function"]["name"] }
    end

    it "shows library_search on the first turn while the toggle is on" do
      expect(kb_visible(kb_on)).to include("library_search")
      expect(kb_visible(kb_on)).not_to include("analyze_image")
    end

    it "hides library_search while the toggle is off, and when it is absent" do
      expect(kb_visible(kb_off)).not_to include("library_search")
      expect(kb_visible({ parameters: {} })).not_to include("library_search")
    end

    it "treats the string \"false\" as off" do
      expect(kb_visible({ parameters: { "library_rag_enabled" => "false" } })).not_to include("library_search")
    end

    it "follows the toggle when it is switched off after being on" do
      session = { parameters: { "library_rag_enabled" => true } }
      expect(kb_visible(session)).to include("library_search")
      session[:parameters]["library_rag_enabled"] = false
      expect(kb_visible(session)).not_to include("library_search")
    end

    it "does not unlock library_search through request_tool" do
      expect(described_class.unlock_request(
        session: kb_off, app_name: "KbApp", app_settings: kb_settings, request_key: "library_search"
      )).to eq([])
      expect(kb_visible(kb_off)).not_to include("library_search")
    end

    it "follows the toggle when the app imports library_search as always visible" do
      always_settings = {
        "progressive_tools" => {
          provider: :openai,
          all_tool_names: ["library_search", "request_tool"],
          always_visible: ["library_search", "request_tool"],
          conditional: []
        }
      }
      visible = ->(session) {
        described_class.visible_tools(app_name: "KbApp", session: session, app_settings: always_settings,
                                      default_tools: kb_tools).map { |t| t["function"]["name"] }
      }
      expect(visible.call(kb_on)).to include("library_search")
      expect(visible.call(kb_off)).not_to include("library_search")
      expect(visible.call({ parameters: {} })).not_to include("library_search")
    end

    it "follows the toggle for an app without progressive metadata" do
      visible = ->(session) {
        described_class.visible_tools(app_name: "KbApp", session: session, app_settings: {},
                                      default_tools: kb_tools).map { |t| t["function"]["name"] }
      }
      expect(visible.call(kb_on)).to include("library_search", "analyze_image")
      expect(visible.call(kb_off)).to contain_exactly("analyze_image", "request_tool")
    end

    it "leaves library_search out of the skill menu and keeps other groups" do
      menu = described_class.skill_menu(app_settings: kb_settings, session: kb_on, app_name: "KbApp").join("\n")
      expect(menu).not_to include("library_search")
      expect(menu).to include("image_analysis")
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

  describe "#handle_request_tool" do
    it "unlocks a whole group and returns a confirmation naming the tools" do
      msg = described_class.handle_request_tool(
        session: session, app_name: app_name, app_settings: app_settings,
        argument_hash: { tool_name: "web_search_tools" }
      )
      expect(msg).to include("Unlocked", "search_web")
      expect(described_class.unlocked?(session: session, app_name: app_name, tool_name: "tavily_fetch")).to be true
    end

    it "accepts string-keyed arguments" do
      msg = described_class.handle_request_tool(
        session: session, app_name: app_name, app_settings: app_settings,
        argument_hash: { "tool_name" => "analyze_image" }
      )
      expect(msg).to include("Unlocked", "analyze_image")
    end

    it "reports when the requested key matches nothing" do
      expect(described_class.handle_request_tool(
        session: session, app_name: app_name, app_settings: app_settings,
        argument_hash: { tool_name: "nope" }
      )).to include("Nothing to unlock")
    end

    it "prompts when no skill name is provided" do
      expect(described_class.handle_request_tool(
        session: session, app_name: app_name, app_settings: app_settings,
        argument_hash: {}
      )).to include("No skill name provided")
    end
  end
end
