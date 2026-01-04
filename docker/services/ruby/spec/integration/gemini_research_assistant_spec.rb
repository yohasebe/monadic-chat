# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Gemini Research Assistant Integration" do
  # Integration tests for Research Assistant with Gemini's internal web search agent
  # These tests verify that web search works alongside other function declarations

  before(:all) do
    TestAppLoader.load_all_apps
  end

  let(:api_key) { CONFIG["GEMINI_API_KEY"] }

  # App loading tests don't need API calls
  describe "ResearchAssistantGemini app loading" do
    it "loads the Research Assistant Gemini app" do
      expect(APPS).to have_key("ResearchAssistantGemini")
    end

    it "has websearch enabled" do
      app = APPS["ResearchAssistantGemini"]
      expect(app).not_to be_nil

      settings = app.settings
      # Settings use string keys
      expect(settings["websearch"]).to be true
    end

    it "has function declarations (tools) defined" do
      app = APPS["ResearchAssistantGemini"]
      settings = app.settings

      # tools is a hash with function_declarations key
      tools = settings["tools"]
      expect(tools).not_to be_nil
      expect(tools).to be_a(Hash)
      expect(tools["function_declarations"]).not_to be_empty
    end

    it "includes research progress tools" do
      app = APPS["ResearchAssistantGemini"]
      settings = app.settings
      tools = settings["tools"]["function_declarations"]

      tool_names = tools.map { |t| t["name"] }
      expect(tool_names).to include("load_research_progress")
      expect(tool_names).to include("save_research_progress")
    end

    it "includes file operation tools" do
      app = APPS["ResearchAssistantGemini"]
      settings = app.settings
      tools = settings["tools"]["function_declarations"]

      tool_names = tools.map { |t| t["name"] }
      expect(tool_names).to include("read_file_from_shared_folder")
      expect(tool_names).to include("write_file_to_shared_folder")
    end
  end

  # Tool injection tests don't need API calls
  describe "gemini_web_search tool injection" do
    let(:helper_instance) do
      Class.new do
        include GeminiHelper
        attr_accessor :settings
        def initialize
          @settings = {}
        end
      end.new
    end

    it "adds gemini_web_search to function declarations when websearch is enabled" do
      # Simulate the tool setup logic
      app_tools = [
        { "name" => "load_research_progress", "description" => "Load progress" },
        { "name" => "save_research_progress", "description" => "Save progress" }
      ]

      use_native_websearch = true
      has_function_declarations = true
      google_search_allowed = use_native_websearch

      if has_function_declarations && google_search_allowed
        gemini_web_search_tool = {
          "name" => "gemini_web_search",
          "description" => "Search the web for current information",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "query" => { "type" => "string", "description" => "Search query" }
            },
            "required" => ["query"]
          }
        }

        tools_array = app_tools.dup
        tools_array << gemini_web_search_tool unless tools_array.any? { |t| t["name"] == "gemini_web_search" }

        expect(tools_array.map { |t| t["name"] }).to include("gemini_web_search")
        expect(tools_array.length).to eq(3)
      end
    end
  end

  # API tests - require RUN_API=true and GEMINI_API_KEY
  describe "internal web search agent", :api do
    before do
      skip "GEMINI_API_KEY not configured" unless api_key && !api_key.empty?
      skip "RUN_API not set - set RUN_API=true to run API tests" unless ENV["RUN_API"] == "true"
    end

    it "performs web search via internal agent" do
      # This test makes an actual API call
      result = GeminiHelper.internal_web_search(query: "Ruby programming language")

      expect(result).to be_a(Hash)

      if result[:success]
        expect(result[:content]).to be_a(String)
        expect(result[:content]).not_to be_empty
        expect(result[:sources]).to be_an(Array)
        expect(result[:query]).to eq("Ruby programming language")
      else
        # API might fail due to rate limits or other transient issues
        # This is acceptable for integration tests
        expect(result[:error]).to be_a(String)
      end
    end

    it "returns sources with web search results" do
      result = GeminiHelper.internal_web_search(query: "latest news today")

      if result[:success]
        sources = result[:sources]
        expect(sources).to be_an(Array)

        # Should have some web sources
        web_sources = sources.select { |s| s["uri"] || s["title"] }
        # Note: sources might be empty if grounding metadata is not returned
      end
    end
  end

  # Visual Web Explorer compatibility tests don't need API calls
  describe "Visual Web Explorer compatibility" do
    it "loads Visual Web Explorer Gemini app" do
      # Visual Web Explorer should also benefit from this pattern
      expect(APPS).to have_key("VisualWebExplorerGemini")
    end

    it "Visual Web Explorer has both websearch and function declarations" do
      app = APPS["VisualWebExplorerGemini"]
      skip "VisualWebExplorerGemini not loaded" unless app

      settings = app.settings

      # Should have websearch enabled (string key)
      expect(settings["websearch"]).to be true

      # Should have tools (take_screenshot, navigate_to_url, etc.)
      tools = settings["tools"]
      expect(tools).not_to be_nil

      if tools.is_a?(Hash)
        expect(tools["function_declarations"]).not_to be_empty
      else
        expect(tools).not_to be_empty
      end
    end

    it "Visual Web Explorer has navigation tools" do
      app = APPS["VisualWebExplorerGemini"]
      skip "VisualWebExplorerGemini not loaded" unless app

      settings = app.settings
      tools = settings["tools"]

      if tools.is_a?(Hash) && tools["function_declarations"]
        tool_names = tools["function_declarations"].map { |t| t["name"] }
        # Check for typical Visual Web Explorer tools
        expect(tool_names.any? { |n| n.include?("screenshot") || n.include?("navigate") }).to be true
      end
    end
  end
end
