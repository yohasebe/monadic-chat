# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'

RSpec.describe GeminiHelper do
  subject(:helper) do
    Class.new do
      include GeminiHelper
    end.new
  end

  describe '#translate_role' do
    it 'maps "user" to "user"' do
      expect(helper.send(:translate_role, "user")).to eq("user")
    end

    it 'maps "assistant" to "model"' do
      expect(helper.send(:translate_role, "assistant")).to eq("model")
    end

    it 'maps "system" to "user"' do
      expect(helper.send(:translate_role, "system")).to eq("user")
    end

    it 'downcases unknown roles' do
      expect(helper.send(:translate_role, "ADMIN")).to eq("admin")
    end

    it 'handles mixed case unknown roles' do
      expect(helper.send(:translate_role, "Observer")).to eq("observer")
    end
  end

  describe '#unwrap_single_markdown_code_block' do
    it 'unwraps a simple code block without language tag' do
      content = "```\nHello, world!\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("Hello, world!")
    end

    it 'unwraps a code block with html language tag' do
      content = "```html\n<div>test</div>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("<div>test</div>")
    end

    it 'unwraps a code block with HTML (uppercase) language tag' do
      content = "```HTML\n<p>paragraph</p>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("<p>paragraph</p>")
    end

    it 'unwraps a code block with xml language tag' do
      content = "```xml\n<root><item/></root>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("<root><item/></root>")
    end

    it 'unwraps a code block with markdown language tag' do
      content = "```markdown\n# Title\nSome text\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("# Title\nSome text")
    end

    it 'returns original content for non-code text' do
      content = "Just regular text, no code blocks here."
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq(content)
    end

    it 'returns original content when there are nested code blocks' do
      content = "```html\n<pre>```nested```</pre>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq(content)
    end

    it 'returns original content for non-string input' do
      expect(helper.send(:unwrap_single_markdown_code_block, nil)).to be_nil
      expect(helper.send(:unwrap_single_markdown_code_block, 42)).to eq(42)
    end

    it 'handles leading and trailing whitespace around the code block' do
      content = "  \n```html\n<div>padded</div>\n```\n  "
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("<div>padded</div>")
    end

    it 'returns original for content with text before code block' do
      content = "Some text before\n```html\n<div>test</div>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq(content)
    end

    it 'returns original for content with text after code block' do
      content = "```html\n<div>test</div>\n```\nSome text after"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq(content)
    end

    it 'unwraps multiline code block content' do
      content = "```html\n<html>\n<head><title>Test</title></head>\n<body>Hello</body>\n</html>\n```"
      result = helper.send(:unwrap_single_markdown_code_block, content)
      expect(result).to eq("<html>\n<head><title>Test</title></head>\n<body>Hello</body>\n</html>")
    end
  end

  describe '#extract_text_from_response' do
    it 'returns nil for nil input' do
      expect(helper.send(:extract_text_from_response, nil)).to be_nil
    end

    it 'returns string directly for non-empty string input' do
      expect(helper.send(:extract_text_from_response, "hello")).to eq("hello")
    end

    it 'returns nil for empty string' do
      expect(helper.send(:extract_text_from_response, "")).to be_nil
    end

    it 'extracts text from Gemini candidates format with parts' do
      response = {
        "candidates" => [{
          "content" => {
            "role" => "model",
            "parts" => [{ "text" => "Generated response" }]
          }
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to eq("Generated response")
    end

    it 'joins multiple text parts' do
      response = {
        "candidates" => [{
          "content" => {
            "role" => "model",
            "parts" => [
              { "text" => "Part one." },
              { "text" => "Part two." }
            ]
          }
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to eq("Part one. Part two.")
    end

    it 'extracts text from direct text field in content' do
      response = {
        "candidates" => [{
          "content" => {
            "role" => "model",
            "text" => "Direct text"
          }
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to eq("Direct text")
    end

    it 'extracts text from direct text field in candidate' do
      response = {
        "candidates" => [{
          "text" => "Candidate text"
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to eq("Candidate text")
    end

    it 'extracts text from content as string' do
      response = {
        "candidates" => [{
          "content" => "String content"
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to eq("String content")
    end

    it 'extracts from simple hash with "text" key' do
      response = { "text" => "Simple text" }
      expect(helper.send(:extract_text_from_response, response)).to eq("Simple text")
    end

    it 'extracts from simple hash with "content" key' do
      response = { "content" => "Content text" }
      expect(helper.send(:extract_text_from_response, response)).to eq("Content text")
    end

    it 'extracts from simple hash with "message" key' do
      response = { "message" => "Message text" }
      expect(helper.send(:extract_text_from_response, response)).to eq("Message text")
    end

    it 'joins array of strings' do
      response = ["first", "second", "third"]
      expect(helper.send(:extract_text_from_response, response)).to eq("first second third")
    end

    it 'still finds text via gather_strings fallback when depth is exceeded' do
      # Create deeply nested structure beyond max_depth
      deeply_nested = { "a" => { "b" => { "c" => { "d" => { "text" => "too deep" } } } } }
      # Even with shallow max_depth, gather_strings fallback at the end
      # recursively collects all string leaves regardless of depth
      result = helper.send(:extract_text_from_response, deeply_nested, 0, 1)
      expect(result).to eq("too deep")
    end

    it 'returns nil for empty candidates array' do
      response = { "candidates" => [] }
      expect(helper.send(:extract_text_from_response, response)).to be_nil
    end

    it 'returns nil for Gemini 2.0 empty content case' do
      response = {
        "candidates" => [{
          "content" => {
            "role" => "model",
            "parts" => []
          }
        }]
      }
      expect(helper.send(:extract_text_from_response, response)).to be_nil
    end

    it 'handles parts array with mixed types' do
      response = {
        "candidates" => [{
          "content" => {
            "parts" => [
              { "text" => "Text part" },
              { "functionCall" => { "name" => "tool", "args" => {} } },
              "String part"
            ]
          }
        }]
      }
      result = helper.send(:extract_text_from_response, response)
      expect(result).to include("Text part")
      expect(result).to include("String part")
    end
  end

  describe '#gather_strings' do
    it 'collects strings from a flat string' do
      out = []
      helper.send(:gather_strings, "hello", out)
      expect(out).to eq(["hello"])
    end

    it 'collects strings from an array' do
      out = []
      helper.send(:gather_strings, ["a", "b", "c"], out)
      expect(out).to eq(["a", "b", "c"])
    end

    it 'collects string values from a hash' do
      out = []
      helper.send(:gather_strings, { "key1" => "val1", "key2" => "val2" }, out)
      expect(out).to eq(["val1", "val2"])
    end

    it 'collects from nested structures' do
      out = []
      data = { "items" => [{ "text" => "found" }, "also found"] }
      helper.send(:gather_strings, data, out)
      expect(out).to include("found")
      expect(out).to include("also found")
    end

    it 'skips empty and whitespace-only strings' do
      out = []
      helper.send(:gather_strings, ["", "  ", "valid"], out)
      expect(out).to eq(["valid"])
    end

    it 'handles nil and numeric values gracefully' do
      out = []
      helper.send(:gather_strings, [nil, 42, "text"], out)
      expect(out).to eq(["text"])
    end
  end

  describe 'MIME detection for auto-attach' do
    # Test the extension-to-MIME mapping used in send_query auto-attach

    def mime_for(filename)
      case File.extname(filename.to_s).downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      else "image/png"
      end
    end

    it 'detects PNG MIME type' do
      expect(mime_for("image.png")).to eq("image/png")
    end

    it 'detects JPG MIME type' do
      expect(mime_for("photo.jpg")).to eq("image/jpeg")
    end

    it 'detects JPEG MIME type' do
      expect(mime_for("photo.jpeg")).to eq("image/jpeg")
    end

    it 'detects GIF MIME type' do
      expect(mime_for("anim.gif")).to eq("image/gif")
    end

    it 'detects WebP MIME type' do
      expect(mime_for("photo.webp")).to eq("image/webp")
    end

    it 'defaults to PNG for unknown extensions' do
      expect(mime_for("file.bmp")).to eq("image/png")
    end

    it 'handles case-insensitive extensions' do
      expect(mime_for("IMAGE.PNG")).to eq("image/png")
      expect(mime_for("photo.JPG")).to eq("image/jpeg")
    end

    it 'handles nil filename' do
      expect(mime_for(nil)).to eq("image/png")
    end
  end
end
