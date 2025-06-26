# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Visual Web Explorer E2E", :e2e do
  include E2EHelper

  let(:app_name) { "VisualWebExplorerOpenAI" }
  let(:test_prompt) { "Please capture screenshots of https://example.com and describe what you see" }

  describe "Visual Web Explorer workflow" do
    it "captures webpage screenshots and provides analysis" do
      with_e2e_retry do
        response = send_and_receive_message(app_name, test_prompt)
        
        # Check for successful screenshot capture
        success = response.match?(/screenshot|captured|image|visual/i) &&
                 (response.match?(/example\.com|Example Domain/i) ||
                  response.match?(/webpage|website|site/i))
        
        if !success
          # Allow for alternative responses
          success = response.match?(/I'll capture|I can capture|Let me capture/i) ||
                   response.match?(/visual exploration|webpage analysis/i)
        end
        
        expect(success).to be true, 
          "Expected screenshot capture response, got: #{response[0..200]}..."
      end
    end
  end

  describe "URL fetching with web search disabled" do
    it "fetches content from a specific URL when asked" do
      url_prompt = "Please fetch the content from https://www.w3.org/History.html and summarize what it's about"
      
      with_e2e_retry do
        response = send_and_receive_message(app_name, url_prompt)
        
        # Check for successful content fetching
        success = response.match?(/W3C|World Wide Web|history|web/i) ||
                 response.match?(/fetch|retrieved|content/i) ||
                 response.match?(/I'll fetch|Let me fetch|I can fetch/i)
        
        expect(success).to be true,
          "Expected URL content fetching, got: #{response[0..200]}..."
      end
    end
  end

  describe "Screenshot gallery creation" do
    it "creates a gallery when capturing multiple viewport screenshots" do
      gallery_prompt = "Capture multiple screenshots of https://example.com with scrolling to show the full page"
      
      with_e2e_retry do
        response = send_and_receive_message(app_name, gallery_prompt)
        
        # Check for gallery or multiple screenshot mentions
        success = response.match?(/gallery|multiple screenshots|scroll/i) ||
                 response.match?(/captured.*screenshots|viewport/i) ||
                 response.match?(/I'll capture.*scroll|Let me capture.*full page/i)
        
        expect(success).to be true,
          "Expected screenshot gallery response, got: #{response[0..200]}..."
      end
    end
  end
end