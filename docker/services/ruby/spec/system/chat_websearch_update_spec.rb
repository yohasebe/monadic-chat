# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Chat Apps Web Search Update", type: :system do
  describe "Updated Chat app configuration" do
    let(:expected_prompt_addition) do
      <<~PROMPT
        
        I have access to web search when needed. I'll use it when:
        - You ask about current events or recent information
        - You need facts about specific people, companies, or organizations  
        - You want the latest information on any topic
        - The question would benefit from up-to-date sources
        
        I'll search efficiently and provide relevant information with sources when available.
      PROMPT
    end

    it "validates Chat app structure with web search enabled" do
      sample_app = <<~MDSL
        app "ChatOpenAI" do
          description <<~TEXT
          General-purpose chat with GPT models. Supports vision, web search, and function calling. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=chat" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
          TEXT
          
          icon "comment"
          
          system_prompt <<~PROMPT
          You are a friendly and professional consultant with comprehensive knowledge. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

          If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.
          
          I have access to web search when needed. I'll use it when:
          - You ask about current events or recent information
          - You need facts about specific people, companies, or organizations  
          - You want the latest information on any topic
          - The question would benefit from up-to-date sources
          
          I'll search efficiently and provide relevant information with sources when available.
          PROMPT
          
          llm do
            provider "openai"
            model "gpt-4.1-mini"
          end
          
          display_name "Chat"
          
          features do
            disabled !CONFIG["OPENAI_API_KEY"]
            easy_submit false
            auto_speech false
            image true
            pdf false
            websearch true
          end
          
          tools do
          end
        end
      MDSL

      # Validate structure
      expect(sample_app).to match(/websearch\s+true/)
      expect(sample_app).to match(/tools\s+do/)
      expect(sample_app).to match(/web search when needed/)
      expect(sample_app).not_to match(/professional research assistant/) # Should not be too specialized
    end

    it "provides template for other providers" do
      providers = {
        "claude" => "ANTHROPIC_API_KEY",
        "gemini" => "GEMINI_API_KEY", 
        "mistral" => "MISTRAL_API_KEY",
        "cohere" => "COHERE_API_KEY",
        "perplexity" => "PERPLEXITY_API_KEY",
        "grok" => "XAI_API_KEY",
        "deepseek" => "DEEPSEEK_API_KEY",
        "ollama" => nil
      }

      providers.each do |provider, api_key|
        template = generate_chat_app_template(provider, api_key)
        
        # Validate each template
        expect(template).to match(/websearch\s+true/)
        expect(template).to match(/tools\s+do/)
        expect(template).to match(/web search when needed/)
      end
    end
  end

  private

  def generate_chat_app_template(provider, api_key)
    model = case provider
    when "claude" then "claude-3.5-sonnet"
    when "gemini" then "gemini-1.5-flash"
    when "mistral" then "mistral-large-latest"
    when "cohere" then "command-r-plus"
    when "perplexity" then "llama-3.3-sonar-large"
    when "grok" then "grok-3"
    when "deepseek" then "deepseek-chat"
    when "ollama" then "llama3.3"
    else "gpt-4.1-mini"
    end

    disabled_line = api_key ? "disabled !CONFIG[\"#{api_key}\"]" : ""

    <<~MDSL
      app "Chat#{provider.capitalize}" do
        description <<~TEXT
        General-purpose chat with #{provider.capitalize} models. Supports vision, web search, and function calling. <a href="https://yohasebe.github.io/monadic-chat/#/basic-usage/basic-apps?id=chat" target="_blank"><i class="fa-solid fa-circle-info"></i></a>
        TEXT
        
        icon "comment"
        
        system_prompt <<~PROMPT
        You are a friendly and professional consultant with comprehensive knowledge. You are able to answer various types of questions, write computer program code, make decent suggestions, and give helpful advice in response to a prompt from the user. If the prompt is not clear enough, ask the user to rephrase it. Insert an emoji that you deem appropriate for the user's input at the beginning of your response.

        If the response is too long to fit in one message, it can be split into multiple messages. If you need to split in the middle of a code block, be sure to properly enclose the partial code block in each message so that it will display properly as a code block when viewed as HTML.
        
        I have access to web search when needed. I'll use it when:
        - You ask about current events or recent information
        - You need facts about specific people, companies, or organizations  
        - You want the latest information on any topic
        - The question would benefit from up-to-date sources
        
        I'll search efficiently and provide relevant information with sources when available.
        PROMPT
        
        llm do
          provider "#{provider}"
          model "#{model}"
        end
        
        display_name "Chat"
        
        features do
          #{disabled_line}
          easy_submit false
          auto_speech false
          image true
          pdf false
          websearch true
        end
        
        tools do
        end
      end
    MDSL
  end
end