# frozen_string_literal: true

require "dotenv/load"
require "rouge"
require "kramdown"
require "cld"
require_relative "./spec_helper"
require_relative "../lib/monadic/utils/string_utils"

RSpec.describe StringUtils do
  # Mock CLD gem to avoid language detection API calls
  before do
    allow(CLD).to receive(:detect_language).and_return({code: "en"})
    
    # Mock CONFIG constant
    stub_const("CONFIG", {
      "ROUGE_THEME" => "github:light"
    })
  end
  
  describe ".detect_language" do
    it "detects the language of text" do
      result = StringUtils.detect_language("Hello, world!")
      expect(result).to eq("en")
    end
    
    it "delegates to CLD gem" do
      expect(CLD).to receive(:detect_language).with("Test text").and_return({code: "fr"})
      result = StringUtils.detect_language("Test text")
      expect(result).to eq("fr")
    end
  end
  
  describe ".normalize_markdown" do
    it "adds blank lines around ordered lists" do
      text = "Some text\n1. First item\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n1. First item\n\nMore text")
    end
    
    it "adds blank lines around code blocks" do
      text = "Some text\n```ruby\nputs 'Hello'\n```\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n```ruby")
      expect(result).to include("```\n\nMore text")
    end
    
    it "adds blank lines around headers" do
      text = "Some text\n## Header\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n## Header")
    end
    
    it "adds blank lines around blockquotes" do
      text = "Some text\n> Quote\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n> Quote")
    end
    
    it "removes excessive blank lines" do
      text = "Some text\n\n\n\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to eq("Some text\n\nMore text")
    end
  end
  
  describe ".markdown_to_html" do
    it "converts markdown to HTML" do
      text = "**Bold text**"
      result = StringUtils.markdown_to_html(text)
      expect(result).to include("<strong>Bold text</strong>")
    end
    
    it "handles code blocks with syntax highlighting" do
      text = "```ruby\nputs 'Hello'\n```"
      result = StringUtils.markdown_to_html(text)
      expect(result).to include("<div class=\"language-ruby highlighter-rouge\">")
      expect(result).to include("<pre class=\"highlight\">")
    end
    
    it "handles non-string inputs" do
      result = StringUtils.markdown_to_html(42)
      expect(result).to eq("42")
    end
    
    context "with MathJax enabled" do
      it "preserves inline MathJax expressions" do
        text = "Equation: $E = mc^2$"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$E = mc^2$")
      end
      
      it "preserves block MathJax expressions" do
        text = "Equation:\n$$E = mc^2$$"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$$E = mc^2$$")
      end
    end
  end
  
  describe StringUtils::DarkThemeFixer do
    let(:mock_theme) do
      Class.new do
        def render(scope:)
          "body { color: white; background-color: #000; }\n.highlight { background-color: #111; }"
        end
      end.new
    end
    
    it "adds transparent background to code elements" do
      fixer = StringUtils::DarkThemeFixer.new(mock_theme, "monokai")
      result = fixer.render(scope: ".highlight")
      
      expect(result).to include("body { color: white; background-color: #000; }")
      expect(result).to include("background-color: transparent !important;")
    end
    
    it "sets the appropriate background color for known themes" do
      fixer = StringUtils::DarkThemeFixer.new(mock_theme, "monokai")
      result = fixer.render(scope: ".highlight")
      
      expect(result).to include("background-color: #272822 !important;")
    end
    
    it "handles unknown themes gracefully" do
      fixer = StringUtils::DarkThemeFixer.new(mock_theme, "unknown_theme")
      result = fixer.render(scope: ".highlight")
      
      # Should not add explicit background for unknown theme
      expect(result).not_to include("background-color: #unknown !important;")
    end
  end
end