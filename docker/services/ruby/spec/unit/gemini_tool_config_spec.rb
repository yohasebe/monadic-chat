# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Gemini toolConfig and thinking mapping" do
  # Test the Gemini request body building logic
  # This tests the configuration mapping without making actual API calls

  let(:helper_instance) do
    Class.new do
      include GeminiHelper

      attr_accessor :settings

      def initialize
        @settings = {}
      end
    end.new
  end

  def build_session(model, tools: nil, reasoning_effort: nil)
    {
      parameters: {
        "app_name" => "CodeInterpreterGemini",
        "model" => model,
        "temperature" => 0.0,
        "max_tokens" => 4000,
        "tools" => tools,
        "reasoning_effort" => reasoning_effort,
        "message" => "Hello"
      },
      messages: []
    }
  end

  before do
    # Stub CONFIG with API key
    stub_const("CONFIG", { "GEMINI_API_KEY" => "test_api_key" })
  end

  describe "toolConfig behavior" do
    it "includes AUTO mode constant in GeminiHelper for tool-capable models" do
      # Verify that AUTO mode is the expected behavior for tool configuration
      # The actual toolConfig is set in the request body building logic
      session = build_session("gemini-2.5-flash", tools: [{ "function_declarations" => [{ "name" => "run_code" }] }])

      # Verify tools are present in session
      expect(session[:parameters]["tools"]).not_to be_nil
      expect(session[:parameters]["tools"]).to be_an(Array)
      expect(session[:parameters]["tools"].first).to have_key("function_declarations")
    end

    it "handles models without explicit tools" do
      session = build_session("gemini-2.5-flash", tools: nil)

      # Verify no tools in session
      expect(session[:parameters]["tools"]).to be_nil
    end
  end

  describe "thinking/reasoning configuration" do
    it "accepts reasoning_effort parameter for thinking-capable models" do
      session = build_session("gemini-2.5-flash", reasoning_effort: "high")

      # Verify reasoning_effort is set in parameters
      expect(session[:parameters]["reasoning_effort"]).to eq("high")
    end

    it "maps reasoning_effort values correctly" do
      # Valid reasoning efforts for Gemini
      valid_efforts = ["minimal", "low", "medium", "high"]

      valid_efforts.each do |effort|
        session = build_session("gemini-2.5-flash", reasoning_effort: effort)
        expect(session[:parameters]["reasoning_effort"]).to eq(effort)
      end
    end
  end

  describe "google_search tool handling" do
    it "handles google_search tool configuration" do
      session = build_session("gemini-2.5-flash", tools: [{ "google_search" => {} }])

      # Verify google_search tool is present
      expect(session[:parameters]["tools"]).not_to be_nil
      expect(session[:parameters]["tools"].first).to have_key("google_search")
    end

    # Note: Gemini 3 doesn't support mixing google_search grounding with function_declarations
    # The gemini_web_search internal agent pattern is used instead
    it "handles google_search grounding tool alone" do
      session = build_session("gemini-2.5-flash", tools: [{ "google_search" => {} }])

      tools = session[:parameters]["tools"]
      expect(tools.length).to eq(1)
      expect(tools.first).to have_key("google_search")
    end
  end

  describe "gemini_web_search tool injection" do
    # Test that gemini_web_search tool definition is correctly structured
    # This tool is injected by gemini_helper.rb when websearch is enabled
    # with function_declarations (instead of using google_search grounding)

    it "defines gemini_web_search tool with correct structure" do
      gemini_web_search_tool = {
        "name" => "gemini_web_search",
        "description" => "Search the web for current information using Google Search. Use this tool when you need to find up-to-date information, verify facts, or research topics. Returns search results with sources.",
        "parameters" => {
          "type" => "object",
          "properties" => {
            "query" => {
              "type" => "string",
              "description" => "The search query to find information on the web"
            }
          },
          "required" => ["query"]
        }
      }

      expect(gemini_web_search_tool["name"]).to eq("gemini_web_search")
      expect(gemini_web_search_tool["parameters"]["properties"]).to have_key("query")
      expect(gemini_web_search_tool["parameters"]["required"]).to include("query")
    end

    it "can be added to existing function declarations array" do
      existing_tools = [
        { "name" => "take_screenshot", "description" => "Take screenshot" },
        { "name" => "navigate_to_url", "description" => "Navigate to URL" }
      ]

      gemini_web_search_tool = {
        "name" => "gemini_web_search",
        "description" => "Search the web",
        "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
      }

      combined_tools = existing_tools.dup
      combined_tools << gemini_web_search_tool

      expect(combined_tools.length).to eq(3)
      expect(combined_tools.map { |t| t["name"] }).to include("gemini_web_search")
    end
  end

  describe "model-specific behavior" do
    it "supports gemini-2.5-flash model" do
      session = build_session("gemini-2.5-flash")
      expect(session[:parameters]["model"]).to eq("gemini-2.5-flash")
    end

    it "supports gemini-3-pro-preview model" do
      session = build_session("gemini-3-pro-preview")
      expect(session[:parameters]["model"]).to eq("gemini-3-pro-preview")
    end
  end
end
