# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"

# Minimal stubs for dependencies
module MonadicHelper
end unless defined?(MonadicHelper)

module Monadic
  module Utils
    module SeleniumHelper
    end
  end
end unless defined?(Monadic::Utils::SeleniumHelper)

RSpec.describe "MonadicSharedTools::WebAutomation" do
  let(:test_class) do
    Class.new do
      include MonadicSharedTools::WebAutomation

      # Stub external dependencies
      def check_selenium_or_error
        nil
      end

      def send_command(command:, container:)
        @last_command = command
        @mock_response || '{"success": true}'
      end

      attr_accessor :mock_response, :last_command
    end
  end

  let(:app) { test_class.new }

  describe "#start_browser headless parameter normalization" do
    before do
      # Mock successful browser start response
      app.mock_response = JSON.generate({
        success: true,
        session_id: "test-session-123",
        screenshot: "screenshot_001.png",
        page_info: { url: "https://example.com", title: "Example" }
      })
    end

    context "with boolean true (default)" do
      it "passes --headless true to Python" do
        app.start_browser(url: "https://example.com")
        expect(app.last_command).to include("--headless true")
      end

      it "does not include novnc_url in response" do
        result = app.start_browser(url: "https://example.com")
        expect(result).not_to have_key(:novnc_url)
      end

      it "includes headless mode message" do
        result = app.start_browser(url: "https://example.com")
        expect(result[:message]).to include("headless mode")
      end
    end

    context "with boolean false" do
      it "passes --headless false to Python" do
        app.start_browser(url: "https://example.com", headless: false)
        expect(app.last_command).to include("--headless false")
      end

      it "includes novnc_url in response" do
        result = app.start_browser(url: "https://example.com", headless: false)
        expect(result[:novnc_url]).to eq("http://localhost:7900")
      end
    end

    context "with string 'false' (LLM may send this)" do
      it "normalizes to headless OFF" do
        app.start_browser(url: "https://example.com", headless: "false")
        expect(app.last_command).to include("--headless false")
      end

      it "includes novnc_url in response" do
        result = app.start_browser(url: "https://example.com", headless: "false")
        expect(result[:novnc_url]).to eq("http://localhost:7900")
      end
    end

    context "with string 'true'" do
      it "normalizes to headless ON" do
        app.start_browser(url: "https://example.com", headless: "true")
        expect(app.last_command).to include("--headless true")
      end

      it "does not include novnc_url" do
        result = app.start_browser(url: "https://example.com", headless: "true")
        expect(result).not_to have_key(:novnc_url)
      end
    end

    context "with nil (parameter omitted)" do
      it "normalizes to headless ON" do
        app.start_browser(url: "https://example.com", headless: nil)
        expect(app.last_command).to include("--headless true")
      end
    end
  end

  describe "#start_browser _image injection" do
    before do
      app.mock_response = JSON.generate({
        success: true,
        session_id: "test-session-123",
        screenshot: "screenshot_001.png",
        page_info: { url: "https://example.com", title: "Example" }
      })
    end

    it "includes _image key when screenshot is present" do
      result = app.start_browser(url: "https://example.com")
      expect(result[:_image]).to eq("screenshot_001.png")
    end

    it "includes gallery_html when screenshot is present" do
      result = app.start_browser(url: "https://example.com")
      expect(result[:gallery_html]).to include("generated_image")
    end
  end

  describe "browser action tools _image injection" do
    before do
      # Initialize browser session state
      app.instance_variable_set(:@browser_action_count, 0)
      app.instance_variable_set(:@browser_last_action, nil)
      app.instance_variable_set(:@browser_consecutive_count, 0)

      app.mock_response = JSON.generate({
        success: true,
        screenshot: "action_screenshot.png",
        page_info: { url: "https://example.com", title: "Example" }
      })
    end

    %i[browser_navigate browser_click browser_type browser_scroll
       browser_press_key browser_back browser_forward].each do |method|
      it "#{method} includes _image in response" do
        args = case method
               when :browser_navigate then { url: "https://example.com" }
               when :browser_click then { selector: "#btn" }
               when :browser_type then { selector: "#input", text: "hello" }
               when :browser_scroll then { direction: "down", amount: 500 }
               when :browser_press_key then { key: "Enter" }
               when :browser_back, :browser_forward then {}
               end

        result = app.send(method, **args)
        expect(result[:_image]).to eq("action_screenshot.png")
      end
    end

    it "browser_screenshot includes _image in response" do
      result = app.browser_screenshot
      expect(result[:_image]).to eq("action_screenshot.png")
    end

    it "browser_select includes _image in response" do
      app.mock_response = JSON.generate({
        success: true,
        screenshot: "select_screenshot.png",
        selected: { value: "opt1" },
        page_info: { url: "https://example.com", title: "Example" }
      })

      result = app.browser_select(selector: "#dropdown", value: "opt1")
      expect(result[:_image]).to eq("select_screenshot.png")
    end
  end

  describe "#create_screenshot_gallery" do
    it "returns empty string for empty array" do
      expect(app.send(:create_screenshot_gallery, [])).to eq("")
    end

    it "includes data-gallery-index and data-gallery-total attributes" do
      html = app.send(:create_screenshot_gallery, ["s1.png", "s2.png"])
      expect(html).to include('data-gallery-index="0"')
      expect(html).to include('data-gallery-index="1"')
      expect(html).to include('data-gallery-total="2"')
    end

    it "wraps each screenshot in generated_image div" do
      html = app.send(:create_screenshot_gallery, ["s1.png"])
      expect(html).to include('<div class="generated_image">')
      expect(html).to include('/data/s1.png')
    end
  end

  describe "#browser_action_guard!" do
    it "allows actions up to MAX_BROWSER_ACTIONS" do
      app.instance_variable_set(:@browser_action_count, 0)
      app.instance_variable_set(:@browser_last_action, nil)
      app.instance_variable_set(:@browser_consecutive_count, 0)
      # Alternate actions to avoid consecutive-same-action limit
      20.times do |i|
        action = i.even? ? "click" : "scroll"
        expect(app.browser_action_guard!(action)).to be_nil
      end
    end

    it "returns error when action limit exceeded" do
      app.instance_variable_set(:@browser_action_count, 20)
      result = app.browser_action_guard!("click")
      expect(result[:success]).to be false
      expect(result[:error]).to include("Action limit reached")
    end

    it "returns error for consecutive same actions exceeding limit" do
      app.instance_variable_set(:@browser_action_count, 0)
      app.instance_variable_set(:@browser_last_action, nil)
      app.instance_variable_set(:@browser_consecutive_count, 0)

      3.times { app.browser_action_guard!("click") }
      result = app.browser_action_guard!("click")
      expect(result[:success]).to be false
      expect(result[:error]).to include("Same action")
    end

    it "resets consecutive count when action changes" do
      app.instance_variable_set(:@browser_action_count, 0)
      app.instance_variable_set(:@browser_last_action, nil)
      app.instance_variable_set(:@browser_consecutive_count, 0)

      3.times { app.browser_action_guard!("click") }
      expect(app.browser_action_guard!("scroll")).to be_nil
    end
  end
end
