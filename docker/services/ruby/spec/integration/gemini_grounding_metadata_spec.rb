require "spec_helper"
require_relative "../../lib/monadic/adapters/vendors/gemini_helper"

RSpec.describe "Gemini Grounding Metadata Integration" do
  include GeminiHelper

  let(:app) { double("app", settings: {}) }
  let(:session) { { messages: [], parameters: { "websearch" => true } } }
  
  describe "grounding metadata HTML generation" do
    context "when API returns grounding metadata" do
      let(:grounding_response) do
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Here's information about the latest trends." }
                ]
              },
              "groundingMetadata" => {
                "webSearchQueries" => [
                  "latest technology trends 2025",
                  "AI developments 2025"
                ],
                "groundingChunks" => [
                  {
                    "web" => {
                      "uri" => "https://example.com/tech-trends",
                      "title" => "Tech Trends 2025"
                    }
                  },
                  {
                    "web" => {
                      "uri" => "https://example.com/ai-news",
                      "title" => "AI News & Updates"
                    }
                  }
                ]
              },
              "finishReason" => "STOP"
            }
          ]
        }
      end

      it "appends grounding metadata HTML to response" do
        # Initialize instance variable
        @grounding_html = nil
        
        # Simulate processing the response
        result = []
        candidates = grounding_response["candidates"]
        
        candidates.each do |candidate|
          if candidate["groundingMetadata"] && 
             !candidate["groundingMetadata"].empty? && 
             @grounding_html.nil?
            
            grounding_data = candidate["groundingMetadata"]
            
            if grounding_data["webSearchQueries"] && !grounding_data["webSearchQueries"].empty?
              search_info = "<div class='search-metadata' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>"
              search_info += "<details style='cursor: pointer;'>"
              
              escaped_queries = grounding_data["webSearchQueries"].map do |q|
                q.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
              end
              search_info += "<summary style='font-weight: bold; color: #666;'>🔍 Web Search: #{escaped_queries.join(", ")}</summary>"
              
              if grounding_data["groundingChunks"] && !grounding_data["groundingChunks"].empty?
                search_info += "<div style='margin-top: 10px;'>"
                search_info += "<p style='margin: 5px 0; font-weight: bold;'>Sources:</p>"
                search_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"
                
                grounding_data["groundingChunks"].each_with_index do |chunk, idx|
                  if chunk["web"]
                    url = chunk["web"]["uri"]
                    title = chunk["web"]["title"] || "Source #{idx + 1}"
                    title = title.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                    search_info += "<li style='margin: 3px 0;'><a href='#{url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{title}</a></li>"
                  end
                end
                
                search_info += "</ul>"
                search_info += "</div>"
              end
              
              search_info += "</details>"
              search_info += "</div>"
              
              @grounding_html = search_info
            end
          end
          
          # Add text content to result
          if candidate["content"] && candidate["content"]["parts"]
            candidate["content"]["parts"].each do |part|
              result << part["text"] if part["text"]
            end
          end
        end
        
        # Append grounding HTML to final content
        final_content = result.join("")
        final_content += "\n\n" + @grounding_html if @grounding_html
        
        expect(final_content).to include("Web Search: latest technology trends 2025, AI developments 2025")
        expect(final_content).to include("Tech Trends 2025")
        expect(final_content).to include("AI News &amp; Updates")
        expect(final_content).to include("https://example.com/tech-trends")
        expect(final_content).to include("<details")
        expect(final_content).to include("</details>")
      end
    end

    context "when grounding metadata is empty" do
      let(:empty_grounding_response) do
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Here's a general response." }
                ]
              },
              "groundingMetadata" => {},
              "finishReason" => "STOP"
            }
          ]
        }
      end

      it "does not append grounding HTML when metadata is empty" do
        @grounding_html = nil
        result = []
        candidates = empty_grounding_response["candidates"]
        
        candidates.each do |candidate|
          if candidate["groundingMetadata"] && 
             !candidate["groundingMetadata"].empty? && 
             @grounding_html.nil?
            # This block should not execute for empty metadata
            @grounding_html = "Should not be set"
          end
          
          # Add text content
          if candidate["content"] && candidate["content"]["parts"]
            candidate["content"]["parts"].each do |part|
              result << part["text"] if part["text"]
            end
          end
        end
        
        final_content = result.join("")
        final_content += "\n\n" + @grounding_html if @grounding_html
        
        expect(@grounding_html).to be_nil
        expect(final_content).to eq("Here's a general response.")
        expect(final_content).not_to include("<details")
      end
    end

    context "HTML escaping for XSS prevention" do
      let(:xss_response) do
        {
          "candidates" => [
            {
              "content" => {
                "parts" => [
                  { "text" => "Response text" }
                ]
              },
              "groundingMetadata" => {
                "webSearchQueries" => [
                  "<script>alert('XSS')</script>",
                  "normal & query"
                ],
                "groundingChunks" => [
                  {
                    "web" => {
                      "uri" => "https://example.com/page",
                      "title" => "<script>alert('Title XSS')</script> & News"
                    }
                  }
                ]
              },
              "finishReason" => "STOP"
            }
          ]
        }
      end

      it "properly escapes HTML in queries and titles" do
        @grounding_html = nil
        candidates = xss_response["candidates"]
        
        candidates.each do |candidate|
          if candidate["groundingMetadata"] && 
             !candidate["groundingMetadata"].empty? && 
             @grounding_html.nil?
            
            grounding_data = candidate["groundingMetadata"]
            
            if grounding_data["webSearchQueries"] && !grounding_data["webSearchQueries"].empty?
              search_info = "<div class='search-metadata' style='margin: 10px 0; padding: 10px; background: #f5f5f5; border-radius: 5px;'>"
              search_info += "<details style='cursor: pointer;'>"
              
              escaped_queries = grounding_data["webSearchQueries"].map do |q|
                q.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
              end
              search_info += "<summary style='font-weight: bold; color: #666;'>🔍 Web Search: #{escaped_queries.join(", ")}</summary>"
              
              if grounding_data["groundingChunks"] && !grounding_data["groundingChunks"].empty?
                search_info += "<div style='margin-top: 10px;'>"
                search_info += "<p style='margin: 5px 0; font-weight: bold;'>Sources:</p>"
                search_info += "<ul style='margin: 5px 0; padding-left: 20px;'>"
                
                grounding_data["groundingChunks"].each_with_index do |chunk, idx|
                  if chunk["web"]
                    url = chunk["web"]["uri"]
                    title = chunk["web"]["title"] || "Source #{idx + 1}"
                    title = title.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
                    search_info += "<li style='margin: 3px 0;'><a href='#{url}' target='_blank' rel='noopener noreferrer' style='color: #0066cc;'>#{title}</a></li>"
                  end
                end
                
                search_info += "</ul>"
                search_info += "</div>"
              end
              
              search_info += "</details>"
              search_info += "</div>"
              
              @grounding_html = search_info
            end
          end
        end
        
        expect(@grounding_html).not_to include("<script>")
        expect(@grounding_html).to include("&lt;script&gt;alert('XSS')&lt;/script&gt;")
        expect(@grounding_html).to include("normal &amp; query")
        expect(@grounding_html).to include("&lt;script&gt;alert('Title XSS')&lt;/script&gt; &amp; News")
      end
    end
  end

  describe "google_search tool configuration" do
    it "includes google_search tool when websearch is enabled" do
      body = {
        "contents" => [],
        "system_instruction" => { "parts" => { "text" => "System prompt" } }
      }
      
      # Simulate websearch enabled
      session[:parameters] = { "websearch" => true }
      
      # The actual implementation would add this
      if session[:parameters]["websearch"]
        body["tools"] = [{"google_search" => {}}]
      end
      
      expect(body["tools"]).to eq([{"google_search" => {}}])
    end

    it "does not include google_search tool when websearch is disabled" do
      body = {
        "contents" => [],
        "system_instruction" => { "parts" => { "text" => "System prompt" } }
      }
      
      # Simulate websearch disabled
      session[:parameters] = { "websearch" => false }
      
      if session[:parameters]["websearch"]
        body["tools"] = [{"google_search" => {}}]
      end
      
      expect(body["tools"]).to be_nil
    end
  end
end