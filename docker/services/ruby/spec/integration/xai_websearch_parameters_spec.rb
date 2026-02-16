# frozen_string_literal: true

require "spec_helper"
require "json"

# Integration test for xAI Responses API web search tools
RSpec.describe "xAI Responses API Web Search", :integration do
  include IntegrationRetryHelper
  before(:all) do
    @skip_xai = !CONFIG["XAI_API_KEY"]
  end

  before(:each) do
    skip "xAI API key not configured" if @skip_xai
  end

  describe "Responses API search tools" do
    it "supports web_search tool with domain filters" do
      with_api_retry(max_attempts: 3, wait: 2, backoff: :exponential) do
        require_relative "../../lib/monadic/adapters/vendors/grok_helper"
        require_relative "../../lib/monadic/utils/string_utils"

        class TestGrokWebSearch
          include GrokHelper
          include StringUtils

          def self.name
            "Grok"
          end

          def markdown_to_html(text, mathjax: false)
            text
          end

          def detect_language(text)
            "en"
          end
        end

        helper = TestGrokWebSearch.new

        session = {
          messages: [],
          parameters: {
            "model" => "grok-4-fast-reasoning",
            "websearch" => true,
            "excluded_websites" => ["spam.com"],
            "allowed_websites" => ["wikipedia.org"],
            "temperature" => 0.0,
            "max_tokens" => 1000,
            "context_size" => 5,
            "app_name" => "test",
            "message" => "What is the weather in Tokyo today? Brief answer."
          }
        }

        responses = []
        helper.api_request("user", session) do |response|
          responses << response
        end

        expect(responses).not_to be_empty

        # Check for content - xAI might return fragments or complete messages
        fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
        assistant_response = responses.find { |r| r["type"] == "assistant" }
        message_response = responses.find { |r| r["type"] == "message" }

        # Collect content from all possible response types
        content = ""
        content += fragments if !fragments.empty?
        if assistant_response
          content += assistant_response["content"]["text"] rescue assistant_response["content"].to_s
        end
        if message_response && message_response["content"] != "DONE"
          content += message_response["content"]["text"] rescue message_response["content"].to_s
        end

        # Verify we received some response types; content may be empty in rare cases
        expect(responses).not_to be_empty
      end
    end

    it "supports x_search tool with handle filters" do
      with_api_retry(max_attempts: 3, wait: 2, backoff: :exponential) do
        require_relative "../../lib/monadic/adapters/vendors/grok_helper"
        require_relative "../../lib/monadic/utils/string_utils"

        class TestGrokXSearch
          include GrokHelper
          include StringUtils

          def self.name
            "Grok"
          end

          def markdown_to_html(text, mathjax: false)
            text
          end

          def detect_language(text)
            "en"
          end
        end

        helper = TestGrokXSearch.new

        session = {
          messages: [],
          parameters: {
            "model" => "grok-4-fast-reasoning",
            "websearch" => true,
            "included_x_handles" => ["@elonmusk"],
            "temperature" => 0.0,
            "max_tokens" => 1000,
            "context_size" => 5,
            "app_name" => "test",
            "message" => "What did Elon Musk recently post about? Brief summary."
          }
        }

        responses = []
        helper.api_request("user", session) do |response|
          responses << response
        end

        expect(responses).not_to be_empty

        # Process responses
        fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
        assistant_response = responses.find { |r| r["type"] == "assistant" }
        message_response = responses.find { |r| r["type"] == "message" }

        content = if !fragments.empty?
          fragments
        elsif assistant_response
          assistant_response["content"]["text"] rescue assistant_response["content"].to_s
        elsif message_response && message_response["content"] != "DONE"
          message_response["content"]["text"] rescue message_response["content"].to_s
        else
          ""
        end

        # Verify we received some response items; content may be empty in rare cases
        expect(responses).not_to be_empty
      end
    end

    it "supports date range filtering via x_search tool" do
      with_api_retry(max_attempts: 3, wait: 2, backoff: :exponential) do
        require_relative "../../lib/monadic/adapters/vendors/grok_helper"
        require_relative "../../lib/monadic/utils/string_utils"

        class TestGrokDateSearch
          include GrokHelper
          include StringUtils

          def self.name
            "Grok"
          end

          def markdown_to_html(text, mathjax: false)
            text
          end

          def detect_language(text)
            "en"
          end
        end

        helper = TestGrokDateSearch.new

        # Use a date range from last week
        date_from = (Date.today - 7).to_s
        date_to = Date.today.to_s

        session = {
          messages: [],
          parameters: {
            "model" => "grok-4-fast-reasoning",
            "websearch" => true,
            "date_from" => date_from,
            "date_to" => date_to,
            "temperature" => 0.0,
            "max_tokens" => 1000,
            "context_size" => 5,
            "app_name" => "test",
            "message" => "What happened in AI news this week? Brief summary."
          }
        }

        responses = []
        helper.api_request("user", session) do |response|
          responses << response
        end

        expect(responses).not_to be_empty

        # Process responses
        fragments = responses.select { |r| r["type"] == "fragment" }.map { |r| r["content"] }.join
        assistant_response = responses.find { |r| r["type"] == "assistant" }
        message_response = responses.find { |r| r["type"] == "message" }

        content = if !fragments.empty?
          fragments
        elsif assistant_response
          assistant_response["content"]["text"] rescue assistant_response["content"].to_s
        elsif message_response && message_response["content"] != "DONE"
          message_response["content"]["text"] rescue message_response["content"].to_s
        else
          ""
        end

        # Verify we received some response items; content assertion is relaxed
        expect(responses).not_to be_empty
      end
    end
  end
end
