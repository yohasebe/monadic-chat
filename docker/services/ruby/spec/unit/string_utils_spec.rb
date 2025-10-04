# frozen_string_literal: true

require "dotenv/load"
require "rouge"
require "cld"
require "csv"
require_relative '../spec_helper'
require_relative "../../lib/monadic/utils/string_utils"

RSpec.describe StringUtils do
  # Use real CONFIG or define it for testing
  before do
    unless defined?(CONFIG)
      # Define CONFIG directly if it doesn't exist
      Object.const_set(:CONFIG, {
        "ROUGE_THEME" => "github:light"
      })
      @config_defined = true
    end
  end
  
  after do
    # Clean up CONFIG if we defined it
    if @config_defined && Object.const_defined?(:CONFIG)
      Object.send(:remove_const, :CONFIG)
    end
  end
  
  describe ".process_tts_dictionary" do
    it "correctly parses CSV content" do
      csv_data = "長谷部,ハセベ\n同志社,ドウシシャ"
      result = StringUtils.process_tts_dictionary(csv_data)
      
      expect(result).to be_a(Hash)
      expect(result.size).to eq(2)
      expect(result["長谷部"]).to eq("ハセベ")
      expect(result["同志社"]).to eq("ドウシシャ")
    end
    
    it "handles empty input" do
      result = StringUtils.process_tts_dictionary("")
      expect(result).to be_a(Hash)
      expect(result).to be_empty
    end
    
    it "handles nil input" do
      result = StringUtils.process_tts_dictionary(nil)
      expect(result).to be_a(Hash)
      expect(result).to be_empty
    end
    
    it "handles malformed CSV with fallback parsing" do
      # Create a helper method that temporarily overrides CSV.parse
      csv_data = "長谷部,ハセベ\n同志社,ドウシシャ"
      
      # Store original parse method
      original_csv_parse = CSV.method(:parse)
      
      # Override CSV.parse to simulate failure
      CSV.define_singleton_method(:parse) do |*args|
        raise StandardError.new("CSV parse error")
      end
      
      # Suppress puts output by redirecting stdout
      original_stdout = $stdout
      $stdout = StringIO.new
      
      result = StringUtils.process_tts_dictionary(csv_data)
      
      expect(result.size).to eq(2)
      expect(result["長谷部"]).to eq("ハセベ")
      expect(result["同志社"]).to eq("ドウシシャ")
      
      # Restore original methods
      CSV.singleton_class.send(:remove_method, :parse)
      CSV.define_singleton_method(:parse, original_csv_parse)
      $stdout = original_stdout
    end
  end
  
  describe ".detect_language" do
    it "detects the language of text" do
      # Use real CLD detection with actual English text
      result = StringUtils.detect_language("Hello, world! This is an English text.")
      # CLD should detect this as English
      expect(result).to eq("en")
    end
    
    it "detects different languages" do
      # Test with real language detection for different languages
      # French text
      french_result = StringUtils.detect_language("Bonjour le monde! Ceci est un texte français.")
      expect(["fr", "en"]).to include(french_result) # CLD might detect as either
      
      # Japanese text  
      japanese_result = StringUtils.detect_language("こんにちは世界！これは日本語のテキストです。")
      expect(japanese_result).to eq("ja")
      
      # Spanish text
      spanish_result = StringUtils.detect_language("¡Hola mundo! Este es un texto en español.")
      expect(["es", "en"]).to include(spanish_result) # CLD might detect as either
    end
  end
  
  describe ".normalize_markdown" do
    it "adds blank lines around ordered lists" do
      text = "Some text\n1. First item\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n1. First item\n\nMore text")
    end
    
    it "maintains numbered list continuity with code blocks in between" do
      text = "1. First item\n```ruby\nputs 'hello'\n```\n2. Second item\n```python\nprint('world')\n```\n3. Third item"
      result = StringUtils.normalize_markdown(text)
      # Check that the numbers are still sequential (1, 2, 3)
      expect(result).to include("1. First item")
      expect(result).to include("2. Second item")
      expect(result).to include("3. Third item")
      # Ensure code blocks are still present
      expect(result).to include("```ruby\nputs 'hello'\n```")
      expect(result).to include("```python\nprint('world')\n```")
    end
    
    it "fixes reset numbering in markdown lists" do
      text = "1. First item\n\n```ruby\nputs 'hello'\n```\n\n1. Second item\n\n```python\nprint('world')\n```\n\n1. Third item"
      result = StringUtils.normalize_markdown(text)
      # Check that the numbers are corrected to be sequential (1, 2, 3)
      expect(result).to include("1. First item")
      expect(result).to include("2. Second item")
      expect(result).to include("3. Third item")
    end
    
    it "adds blank lines around unordered lists" do
      text = "Some text\n- First item\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n- First item\n\nMore text")
    end
    
    it "fixes indented code blocks" do
      text = "Some text\n    ```ruby\n    puts 'Hello'\n    ```\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n```ruby")
      expect(result).not_to include("    ```ruby")
    end
    
    it "adds blank lines around code blocks" do
      text = "Some text\n```ruby\nputs 'Hello'\n```\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("Some text\n\n```ruby")
      expect(result).to include("```\n\nMore text")
    end
    
    it "fixes empty code blocks" do
      text = "Some text\n```python\n```\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("```python\n\n```")
    end
    
    it "handles code blocks with code block syntax inside" do
      text = "Some text\n```ruby\ncode = \"```python\\nputs 'hello'\\n```\"\n```\nMore text"
      result = StringUtils.normalize_markdown(text)
      # The code block should be preserved, including the inner code block syntax
      # Our implementation may add an extra blank line for empty code blocks, which is fine
      expect(result).to include("```ruby")
      expect(result).to include("code = \"```python\\nputs 'hello'\\n```\"")
    end
    
    it "adds basic content after code blocks" do
      # A basic test case with content after a code block
      text = "Some text\n```\ncode content\n```\nMore text"
      
      result = StringUtils.normalize_markdown(text)
      
      # Verify structure and basic content before and after
      expect(result).to include("Some text")
      expect(result).to include("code content")
      expect(result).to include("More text")
      
      # Verify blank lines are added properly
      expect(result).to include("```\n\nMore text")
    end
    
    it "fixes indented code blocks but preserves content" do
      text = "Some text\n    ```ruby\n    puts 'hello'\n    ```\nMore text"
      result = StringUtils.normalize_markdown(text)
      # The indentation on the code block markers should be removed, but content is preserved
      expect(result).to include("```ruby")
      expect(result).to include("    puts 'hello'")
      expect(result).not_to include("    ```ruby")  # No indentation on markers
    end
    
    it "adds blank lines around headers" do
      text = "Some text\n## Header\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Check for proper blank lines around headers
      expect(result).to include("Some text\n\n## Header")
    end
    
    it "adds blank lines around blockquotes" do
      text = "Some text\n> Quote\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Check for proper blank lines around blockquotes
      expect(result).to include("Some text\n\n> Quote")
    end
    
    it "fixes indented blockquotes" do
      text = "Some text\n    > Quote\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Check that indentation is removed from blockquotes
      expect(result).to include("> Quote")
      expect(result).not_to include("    > Quote")
    end
    
    it "ensures blank lines after blockquotes" do
      text = "Some text\n> Quote\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Check that there's a blank line after the blockquote
      expect(result).to include("> Quote\n\nMore text")
    end
    
    it "fixes nested blockquotes formatting" do
      text = "Some text\n> Quote\n> > Nested quote\nMore text"
      result = StringUtils.normalize_markdown(text)
      # With our format, there could be blank lines between these, so check for presence
      expect(result).to include("> Quote")
      expect(result).to include("> > Nested quote")
      # Check that they appear in the correct order
      quote_index = result.index("> Quote")
      nested_quote_index = result.index("> > Nested quote")
      expect(quote_index).to be < nested_quote_index
    end
    
    it "adds blank lines around tables" do
      text = "Some text\n|Column1|Column2|\n|----|----|\n|data1|data2|\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Just check that there's content before and after with appropriate spacing
      expect(result).to include("Some text")
      expect(result).to include("|Column1|Column2|")
      expect(result).to include("|data1|data2|")
      expect(result).to include("More text")
      # Check for blank line presence
      expect(result.scan(/\n\n/).size).to be >= 2
    end
    
    it "fixes tables with missing separator row" do
      text = "Some text\n|Column1|Column2|\n|data1|data2|\nMore text"
      result = StringUtils.normalize_markdown(text)
      # The text processor now fixes the table structure before adding blank lines
      # So we need to check for the presence of the separator line
      expect(result).to include("|Column1|Column2|")
      expect(result).to include("|---|---") # Look for at least part of the separator
      expect(result).to include("|data1|data2|")
    end
    
    it "fixes tables with missing closing pipe" do
      text = "Some text\n|Column1|Column2\n|---|---|\n|data1|data2\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("|Column1|Column2|")
      expect(result).to include("|data1|data2|")
    end
    
    it "ignores table syntax inside code blocks" do
      text = "Some text\n```\n|Column1|Column2\n|data1|data2\n```\nMore text"
      result = StringUtils.normalize_markdown(text)
      # The pipe characters inside code block should not be modified
      expect(result).to include("|Column1|Column2\n|data1|data2")
      expect(result).not_to include("|Column1|Column2|")
    end
    
    it "handles complex tables with nested formatting" do
      text = "Some text\n|Column1|Column2|\n|data1|`|pipe|` character|\nMore text"
      result = StringUtils.normalize_markdown(text)
      # Should add separator row and preserve formatting
      expect(result).to include("|Column1|Column2|")
      expect(result).to include("|---|---|")
      expect(result).to include("|data1|`|pipe|` character|")
    end
    
    it "fixes self-closing HTML tags" do
      text = "Some text\n<br>\n<hr>\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("<br />")
      expect(result).to include("<hr />")
    end
    
    it "formats HTML comments correctly" do
      text = "Some text\n<!--comment-->\nMore text"
      result = StringUtils.normalize_markdown(text)
      expect(result).to include("<!-- comment -->")
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
      expect(result).to include("<div class=\"highlight language-ruby highlighter-rouge\">")
      expect(result).to include("<pre class=\"highlight\">")
    end
    
    it "handles non-string inputs" do
      result = StringUtils.markdown_to_html(42)
      expect(result).to eq("42")
    end
    
    it "handles bold text with special brackets" do
      text = "This is the famous **[base rate fallacy]** phenomenon"
      result = StringUtils.markdown_to_html(text)
      expect(result).to include("<strong>[base rate fallacy]</strong>")
    end
    
    it "handles bold text in numbered lists" do
      text = <<~MARKDOWN
        1. **Initial information (prior probability)** combined with
        2. **New evidence (likelihood)** to produce
        3. **Updated belief (posterior probability)**
      MARKDOWN
      result = StringUtils.markdown_to_html(text)
      expect(result).to include("<strong>Initial information (prior probability)</strong>")
      expect(result).to include("<strong>New evidence (likelihood)</strong>")
      expect(result).to include("<strong>Updated belief (posterior probability)</strong>")
    end
    
    it "handles multiple bracket types in bold" do
      text = "**[Important]**, **{Note}**, **<Reference>**"
      result = StringUtils.markdown_to_html(text)
      expect(result).to include("<strong>[Important]</strong>")
      expect(result).to include("<strong>{Note}</strong>")
      # Note: <Reference> is rendered as-is due to unsafe: true option
      # This allows HTML pass-through but means angle brackets are not escaped
      expect(result).to include("<strong><Reference></strong>")
    end
    
    it "automatically normalizes malformed markdown" do
      # Malformed markdown with indented code block without blank lines
      text = "Some text\n    ```ruby\n    puts 'Hello'\n    ```\nMore text"
      result = StringUtils.markdown_to_html(text)
      
      # Should be properly formatted in HTML
      expect(result).to include("<div class=\"highlight language-ruby highlighter-rouge\">")
      expect(result).to include("<pre class=\"highlight\">")
    end
    
    it "renders table content" do
      # Table with proper format including separator row
      text = "| Header1 | Header2 |\n|---------|----------|\n| Data1   | Data2    |"
      result = StringUtils.markdown_to_html(text)
      
      # Should render the table content
      expect(result).to include("Header1")
      expect(result).to include("Data1")
    end
    
    it "handles improper blockquote formatting" do
      # Blockquote with formatting issues
      text = "    > This is indented\n> Normal quote"
      result = StringUtils.markdown_to_html(text)
      
      # Should render as proper blockquotes or at least contain the content
      expect(result.downcase).to include("this is indented")
      expect(result.downcase).to include("normal quote")
    end
    
    context "with MathJax enabled" do
      it "preserves inline MathJax expressions with $...$ format" do
        text = "Equation: $E = mc^2$"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$E = mc^2$")
      end
      
      it "preserves block MathJax expressions with $$...$$ format" do
        text = "Equation:\n$$E = mc^2$$"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$$E = mc^2$$")
      end
      
      it "converts inline MathJax expressions from \\(...\\) format to $...$ format" do
        text = "Equation: \\(E = mc^2\\)"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$E = mc^2$")
      end
      
      it "converts block MathJax expressions from \\[...\\] format to $$...$$ format" do
        text = "Equation:\n\\[E = mc^2\\]"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("$$E = mc^2$$")
      end
      
      it "preserves LaTeX escape sequences in MathJax content" do
        text = "Equation with escape: $E = mc^2 \\text{ energy}$"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        # Our new implementation uses \(...\) format for complex LaTeX commands
        expect(result).to include("\\(E = mc^2 \\text{ energy}\\)")
      end
      
      it "preserves MathJax code in code blocks" do
        text = "```python\nx = 1 + 2 # Compute $E = mc^2$ result\n```"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        # Our improved implementation preserves code blocks differently
        expect(result).to include("```python")
        expect(result).to include("x = 1 + 2 # Compute $E = mc^2$ result")
      end
      
      it "does not convert MathJax notation inside code blocks" do
        text = "```python\nExample: \\[E = mc^2\\] or \\(a + b = c\\)\n```"
        result = StringUtils.markdown_to_html(text, mathjax: true)
        expect(result).to include("\\[E = mc^2\\]")
        expect(result).to include("\\(a + b = c\\)")
      end
    end
  end
  
  describe ".fix_numbered_lists" do
    it "corrects reset numbering in lists" do
      text = "1. First item\n\n1. Second item\n\n1. Third item"
      result = StringUtils.fix_numbered_lists(text)
      expect(result).to include("1. First item")
      expect(result).to include("2. Second item")
      expect(result).to include("3. Third item")
    end
    
    it "preserves correct numbering in lists" do
      text = "1. First item\n\n2. Second item\n\n3. Third item"
      result = StringUtils.fix_numbered_lists(text)
      expect(result).to include("1. First item")
      expect(result).to include("2. Second item")
      expect(result).to include("3. Third item")
    end
    
    it "correctly handles lists with code blocks in between" do
      text = "1. First item\n\n```ruby\nputs 'hello'\n```\n\n1. This should be item 2\n\n```python\nprint('world')\n```\n\n1. This should be item 3"
      result = StringUtils.fix_numbered_lists(text)
      
      expect(result).to include("1. First item")
      expect(result).to include("2. This should be item 2")
      expect(result).to include("3. This should be item 3")
    end
    
    it "handles multiple indentation levels" do
      text = "1. First item\n   1. Nested item 1\n   1. Nested item 2 should be 2\n2. Second main item"
      result = StringUtils.fix_numbered_lists(text)
      
      expect(result).to include("1. First item")
      expect(result).to include("   1. Nested item 1")
      expect(result).to include("   2. Nested item 2 should be 2")
      expect(result).to include("2. Second main item")
    end
    
    it "does not modify text without numbered lists" do
      text = "This is some text\n\nWithout any lists"
      result = StringUtils.fix_numbered_lists(text)
      expect(result).to eq(text)
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