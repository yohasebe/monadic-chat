# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/claude_helper'

RSpec.describe ClaudeHelper do
  subject(:helper) do
    Class.new do
      include ClaudeHelper
    end.new
  end

  describe '.convert_tool_to_claude_format' do
    it 'returns non-hash input unchanged' do
      expect(ClaudeHelper.convert_tool_to_claude_format("not a hash")).to eq("not a hash")
    end

    it 'passes through tools already in Claude custom format' do
      tool = { "type" => "custom", "name" => "my_tool", "input_schema" => {} }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end

    it 'passes through native web_search tool' do
      tool = { "type" => "web_search_20250305", "max_uses" => 3 }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end

    it 'passes through native code_execution tool' do
      tool = { "type" => "code_execution", "sandbox" => "default" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end

    it 'passes through bash_ prefixed tools' do
      tool = { "type" => "bash_20250124", "name" => "bash" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end

    it 'passes through text_editor_ prefixed tools' do
      tool = { "type" => "text_editor_20250124", "name" => "str_replace_editor" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end

    it 'converts OpenAI function format to Claude custom format' do
      openai_tool = {
        "type" => "function",
        "function" => {
          "name" => "get_weather",
          "description" => "Get weather data",
          "parameters" => {
            "type" => "object",
            "properties" => { "city" => { "type" => "string" } },
            "required" => ["city"]
          }
        }
      }
      result = ClaudeHelper.convert_tool_to_claude_format(openai_tool)
      expect(result["type"]).to eq("custom")
      expect(result["name"]).to eq("get_weather")
      expect(result["description"]).to eq("Get weather data")
      expect(result["input_schema"]["properties"]).to have_key("city")
    end

    it 'provides default input_schema when OpenAI function has no parameters' do
      openai_tool = {
        "type" => "function",
        "function" => {
          "name" => "no_params_tool",
          "description" => "A tool with no params"
        }
      }
      result = ClaudeHelper.convert_tool_to_claude_format(openai_tool)
      expect(result["input_schema"]).to eq({
        "type" => "object",
        "properties" => {},
        "required" => []
      })
    end

    it 'handles symbol keys in OpenAI format' do
      openai_tool = {
        type: "function",
        function: {
          name: "sym_tool",
          description: "Tool with symbol keys",
          parameters: { "type" => "object", "properties" => {} }
        }
      }
      result = ClaudeHelper.convert_tool_to_claude_format(openai_tool)
      expect(result["type"]).to eq("custom")
      expect(result["name"]).to eq("sym_tool")
    end

    it 'fixes type for tool with name but wrong type' do
      tool = { "type" => "wrong", "name" => "my_tool", "description" => "desc" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result["type"]).to eq("custom")
      expect(result["name"]).to eq("my_tool")
    end

    it 'adds default input_schema for tool with name but no schema' do
      tool = { "type" => "wrong", "name" => "no_schema_tool" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result["input_schema"]).to eq({
        "type" => "object",
        "properties" => {},
        "required" => []
      })
    end

    it 'preserves existing input_schema when fixing type' do
      schema = { "type" => "object", "properties" => { "x" => { "type" => "integer" } } }
      tool = { "type" => "wrong", "name" => "has_schema", "input_schema" => schema }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result["input_schema"]).to eq(schema)
    end

    it 'returns tool unchanged when it has no name and is not a function' do
      tool = { "type" => "unknown", "data" => "value" }
      result = ClaudeHelper.convert_tool_to_claude_format(tool)
      expect(result).to eq(tool)
    end
  end

  describe '#sanitize_data' do
    it 'cleans invalid UTF-8 from strings' do
      bad_string = "hello\xFFworld".dup.force_encoding('UTF-8')
      result = helper.send(:sanitize_data, bad_string)
      expect(result).to be_a(String)
      expect(result.valid_encoding?).to be true
      expect(result).to include("hello")
      expect(result).to include("world")
    end

    it 'returns valid UTF-8 strings unchanged' do
      good_string = "Hello, world!"
      result = helper.send(:sanitize_data, good_string)
      expect(result).to eq(good_string)
    end

    it 'recursively cleans strings in hashes' do
      data = {
        "name" => "valid",
        "nested" => {
          "value" => "has\xFFbad".dup.force_encoding('UTF-8')
        }
      }
      result = helper.send(:sanitize_data, data)
      expect(result["nested"]["value"].valid_encoding?).to be true
      expect(result["name"]).to eq("valid")
    end

    it 'recursively cleans strings in arrays' do
      data = ["good", "has\xFFbad".dup.force_encoding('UTF-8'), "also good"]
      result = helper.send(:sanitize_data, data)
      expect(result.all? { |s| s.valid_encoding? }).to be true
      expect(result[0]).to eq("good")
      expect(result[2]).to eq("also good")
    end

    it 'handles mixed nested structures' do
      data = {
        "items" => [
          { "text" => "ok\xFEhere".dup.force_encoding('UTF-8') },
          "plain"
        ]
      }
      result = helper.send(:sanitize_data, data)
      expect(result["items"][0]["text"].valid_encoding?).to be true
      expect(result["items"][1]).to eq("plain")
    end

    it 'passes non-string non-collection types through' do
      expect(helper.send(:sanitize_data, 42)).to eq(42)
      expect(helper.send(:sanitize_data, true)).to eq(true)
      expect(helper.send(:sanitize_data, nil)).to be_nil
    end
  end

  describe '#get_extension_from_content_type' do
    it 'returns .docx for Word documents' do
      result = helper.send(:get_extension_from_content_type,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
      expect(result).to eq(".docx")
    end

    it 'returns .xlsx for Excel spreadsheets' do
      result = helper.send(:get_extension_from_content_type,
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(result).to eq(".xlsx")
    end

    it 'returns .pptx for PowerPoint presentations' do
      result = helper.send(:get_extension_from_content_type,
        "application/vnd.openxmlformats-officedocument.presentationml.presentation")
      expect(result).to eq(".pptx")
    end

    it 'returns .pdf for PDF documents' do
      result = helper.send(:get_extension_from_content_type, "application/pdf")
      expect(result).to eq(".pdf")
    end

    it 'returns .txt for plain text' do
      result = helper.send(:get_extension_from_content_type, "text/plain")
      expect(result).to eq(".txt")
    end

    it 'returns .json for JSON content' do
      result = helper.send(:get_extension_from_content_type, "application/json")
      expect(result).to eq(".json")
    end

    it 'returns empty string for nil' do
      result = helper.send(:get_extension_from_content_type, nil)
      expect(result).to eq("")
    end

    it 'returns empty string for unknown content type' do
      result = helper.send(:get_extension_from_content_type, "image/png")
      expect(result).to eq("")
    end

    it 'matches content types with charset parameters' do
      result = helper.send(:get_extension_from_content_type, "application/pdf; charset=utf-8")
      expect(result).to eq(".pdf")
    end
  end
end
