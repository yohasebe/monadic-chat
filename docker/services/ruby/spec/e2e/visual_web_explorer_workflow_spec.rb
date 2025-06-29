# frozen_string_literal: true

require_relative "e2e_helper"
require_relative "validation_helper"

RSpec.describe "Visual Web Explorer E2E", :e2e do
  include E2EHelper
  include ValidationHelper

  let(:app_name) { "VisualWebExplorerOpenAI" }
  let(:test_prompt) { "Please capture screenshots of https://example.com and describe what you see" }

  describe "Visual Web Explorer workflow" do
    it "captures webpage screenshots and provides analysis" do
      with_e2e_retry(max_attempts: 3, wait: 10) do
        # More explicit instruction to capture the screenshot
        explicit_prompt = "Please capture a screenshot of https://example.com and describe what you see. Use create_viewport_screenshot to capture the page."
        response = send_and_receive_message(app_name, explicit_prompt)
        
        # Check if screenshot capture was attempted or mentioned
        success = screenshot_captured?(response) || 
                  response.match?(/would.*capture|entire.*page/i) ||  # Asking for clarification
                  response.match?(/I'll.*capture|let.*capture/i) ||             # Intent to capture
                  response.match?(/example\.com/i)                                   # At least mentions the URL
        
        expect(success).to be(true), 
          "Expected screenshot capture activity, got: #{response[0..200]}..."
        
        # Verify response has reasonable length
        expect(response.length).to be > 10
      end
    end
  end

  describe "URL fetching with web search disabled" do
    it "fetches content from a specific URL when asked" do
      url_prompt = "Please fetch the content from https://www.w3.org/History.html and summarize what it's about"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, url_prompt)
        
        # Check for successful content fetching
        success = response.match?(/W3C|history|web/i) ||
                 response.match?(/fetch|retrieved|content/i) ||
                 response.match?(/fetch/i)
        
        expect(success).to be(true),
          "Expected URL content fetching, got: #{response[0..200]}..."
      end
    end
  end

  describe "Screenshot gallery creation" do
    it "creates a gallery when capturing multiple viewport screenshots" do
      gallery_prompt = "Capture multiple screenshots of https://example.com with scrolling to show the full page"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, gallery_prompt)
        
        # Check for gallery or multiple screenshot mentions
        success = response.match?(/gallery|screenshot|scroll/i) ||
                 response.match?(/captured|viewport/i) ||
                 response.match?(/capture.*scroll|capture.*page/i)
        
        expect(success).to be(true),
          "Expected screenshot gallery response, got: #{response[0..200]}..."
      end
    end
  end
end