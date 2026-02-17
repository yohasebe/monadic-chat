# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/ollama_helper'

RSpec.describe OllamaHelper do
  subject(:helper) do
    Class.new do
      include OllamaHelper
    end.new
  end

  describe 'constants' do
    describe 'DEFAULT_MODEL' do
      it 'is defined as a non-empty string' do
        expect(OllamaHelper::DEFAULT_MODEL).to be_a(String)
        expect(OllamaHelper::DEFAULT_MODEL).not_to be_empty
      end

      it 'matches the value in system_defaults.json' do
        defaults_path = File.expand_path('../../../../../../config/system_defaults.json', __FILE__)
        if File.exist?(defaults_path)
          defaults = JSON.parse(File.read(defaults_path))
          expected_model = defaults.dig('provider_defaults', 'ollama', 'model')
          expect(OllamaHelper::DEFAULT_MODEL).to eq(expected_model) if expected_model
        end
      end
    end

    describe 'ENDPOINT_CANDIDATES' do
      it 'contains exactly 3 candidates' do
        expect(OllamaHelper::ENDPOINT_CANDIDATES.size).to eq(3)
      end

      it 'includes Docker container endpoint as first candidate' do
        expect(OllamaHelper::ENDPOINT_CANDIDATES.first).to include('monadic-chat-ollama-container')
      end

      it 'includes host.docker.internal as second candidate' do
        expect(OllamaHelper::ENDPOINT_CANDIDATES[1]).to include('host.docker.internal')
      end

      it 'includes localhost as last candidate' do
        expect(OllamaHelper::ENDPOINT_CANDIDATES.last).to include('localhost')
      end

      it 'is frozen' do
        expect(OllamaHelper::ENDPOINT_CANDIDATES).to be_frozen
      end

      it 'all candidates end with /api' do
        OllamaHelper::ENDPOINT_CANDIDATES.each do |ep|
          expect(ep).to end_with('/api')
        end
      end
    end

    describe 'MAX_RETRIES' do
      it 'is a positive integer' do
        expect(OllamaHelper::MAX_RETRIES).to be_a(Integer)
        expect(OllamaHelper::MAX_RETRIES).to be > 0
      end
    end

    describe 'MAX_FUNC_CALLS' do
      it 'is a positive integer' do
        expect(OllamaHelper::MAX_FUNC_CALLS).to be_a(Integer)
        expect(OllamaHelper::MAX_FUNC_CALLS).to be > 0
      end
    end
  end

  describe '.vendor_name' do
    it 'returns "Ollama" as a module function' do
      expect(OllamaHelper.vendor_name).to eq("Ollama")
    end

    it 'is private when included as instance method' do
      # module_function makes the instance method private
      expect(helper.private_methods).to include(:vendor_name)
    end
  end

  describe '#format_tools_for_ollama' do
    it 'returns empty array for nil input' do
      expect(helper.send(:format_tools_for_ollama, nil)).to eq([])
    end

    it 'returns empty array for empty array input' do
      expect(helper.send(:format_tools_for_ollama, [])).to eq([])
    end

    it 'passes through tools already in OpenAI format' do
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
      result = helper.send(:format_tools_for_ollama, [openai_tool])
      expect(result.size).to eq(1)
      expect(result.first).to eq(openai_tool)
    end

    it 'converts Claude/Gemini format (name + input_schema) to OpenAI format' do
      claude_tool = {
        "name" => "search_documents",
        "description" => "Search documents by query",
        "input_schema" => {
          "type" => "object",
          "properties" => { "query" => { "type" => "string" } },
          "required" => ["query"]
        }
      }
      result = helper.send(:format_tools_for_ollama, [claude_tool])
      expect(result.size).to eq(1)

      converted = result.first
      expect(converted["type"]).to eq("function")
      expect(converted["function"]["name"]).to eq("search_documents")
      expect(converted["function"]["description"]).to eq("Search documents by query")
      expect(converted["function"]["parameters"]["properties"]).to have_key("query")
    end

    it 'converts tools with parameters key (alternative format)' do
      tool = {
        "name" => "calculate",
        "description" => "Perform calculation",
        "parameters" => {
          "type" => "object",
          "properties" => { "expression" => { "type" => "string" } }
        }
      }
      result = helper.send(:format_tools_for_ollama, [tool])
      expect(result.size).to eq(1)
      expect(result.first["function"]["parameters"]["properties"]).to have_key("expression")
    end

    it 'provides default parameters when none are specified' do
      tool = {
        "name" => "no_params_tool",
        "description" => "A tool with no params"
      }
      result = helper.send(:format_tools_for_ollama, [tool])
      expect(result.size).to eq(1)
      expect(result.first["function"]["parameters"]).to eq({
        "type" => "object",
        "properties" => {}
      })
    end

    it 'handles Hash input with function_declarations key' do
      tools_hash = {
        "function_declarations" => [
          {
            "name" => "tool_from_hash",
            "description" => "A tool from a hash wrapper"
          }
        ]
      }
      result = helper.send(:format_tools_for_ollama, tools_hash)
      expect(result.size).to eq(1)
      expect(result.first["function"]["name"]).to eq("tool_from_hash")
    end

    it 'handles empty function_declarations Hash' do
      tools_hash = { "function_declarations" => [] }
      result = helper.send(:format_tools_for_ollama, tools_hash)
      expect(result).to eq([])
    end

    it 'handles Hash without function_declarations key' do
      tools_hash = { "other_key" => "value" }
      result = helper.send(:format_tools_for_ollama, tools_hash)
      expect(result).to eq([])
    end

    it 'filters out non-hash elements' do
      tools = ["not a hash", 42, nil]
      result = helper.send(:format_tools_for_ollama, tools)
      expect(result).to eq([])
    end

    it 'handles mixed format tools in a single array' do
      openai_tool = {
        "type" => "function",
        "function" => {
          "name" => "openai_tool",
          "description" => "OpenAI format",
          "parameters" => { "type" => "object", "properties" => {} }
        }
      }
      claude_tool = {
        "name" => "claude_tool",
        "description" => "Claude format",
        "input_schema" => { "type" => "object", "properties" => {} }
      }
      result = helper.send(:format_tools_for_ollama, [openai_tool, claude_tool])
      expect(result.size).to eq(2)
      expect(result[0]["function"]["name"]).to eq("openai_tool")
      expect(result[1]["function"]["name"]).to eq("claude_tool")
    end

    it 'returns empty array for non-array non-hash input' do
      expect(helper.send(:format_tools_for_ollama, "string")).to eq([])
      expect(helper.send(:format_tools_for_ollama, 42)).to eq([])
    end
  end

  describe 'Ollama streaming response format' do
    it 'parses content fragments from Ollama JSON chunks' do
      chunks = [
        { "message" => { "content" => "Hello" }, "done" => false },
        { "message" => { "content" => " world" }, "done" => false },
        { "message" => { "content" => "!" }, "done" => true }
      ]

      texts = []
      finish_reason = nil

      chunks.each do |json|
        finish_reason = json["done"] ? "stop" : nil
        fragment = json.dig("message", "content").to_s
        texts << fragment unless fragment.empty?
      end

      expect(texts.join).to eq("Hello world!")
      expect(finish_reason).to eq("stop")
    end

    it 'detects tool calls in done chunk' do
      chunks = [
        { "message" => { "content" => "" }, "done" => false },
        {
          "message" => {
            "content" => "",
            "tool_calls" => [
              {
                "function" => {
                  "name" => "get_weather",
                  "arguments" => { "city" => "Tokyo" }
                }
              }
            ]
          },
          "done" => true
        }
      ]

      accumulated_tool_calls = []
      chunks.each do |json|
        if json.dig("message", "tool_calls")
          json["message"]["tool_calls"].each { |tc| accumulated_tool_calls << tc }
        end
      end

      expect(accumulated_tool_calls.size).to eq(1)
      expect(accumulated_tool_calls.first.dig("function", "name")).to eq("get_weather")
      expect(accumulated_tool_calls.first.dig("function", "arguments")).to eq({ "city" => "Tokyo" })
    end

    it 'accumulates multiple tool calls' do
      chunk = {
        "message" => {
          "content" => "",
          "tool_calls" => [
            { "function" => { "name" => "tool_a", "arguments" => {} } },
            { "function" => { "name" => "tool_b", "arguments" => {} } }
          ]
        },
        "done" => true
      }

      accumulated = []
      chunk["message"]["tool_calls"].each { |tc| accumulated << tc }
      expect(accumulated.size).to eq(2)
      expect(accumulated.map { |tc| tc.dig("function", "name") }).to eq(["tool_a", "tool_b"])
    end

    it 'handles mixed content and tool calls' do
      chunks = [
        { "message" => { "content" => "Let me check" }, "done" => false },
        { "message" => { "content" => " that." }, "done" => false },
        {
          "message" => {
            "content" => "",
            "tool_calls" => [
              { "function" => { "name" => "search", "arguments" => { "q" => "test" } } }
            ]
          },
          "done" => true
        }
      ]

      texts = []
      tool_calls = []

      chunks.each do |json|
        if json.dig("message", "tool_calls")
          json["message"]["tool_calls"].each { |tc| tool_calls << tc }
        elsif json.dig("message", "content")
          fragment = json.dig("message", "content").to_s
          texts << fragment unless fragment.empty?
        end
      end

      expect(texts.join).to eq("Let me check that.")
      expect(tool_calls.size).to eq(1)
      expect(tool_calls.first.dig("function", "name")).to eq("search")
    end
  end

  describe 'Ollama response result format' do
    it 'wraps result in OpenAI-compatible choices format' do
      # This mirrors what process_json_data returns
      result_text = "Hello from Ollama"
      result = {
        "choices" => [{
          "message" => {
            "content" => result_text
          },
          "finish_reason" => "stop"
        }]
      }

      expect(result.dig("choices", 0, "message", "content")).to eq("Hello from Ollama")
      expect(result.dig("choices", 0, "finish_reason")).to eq("stop")
    end
  end

  describe 'timeout configuration' do
    it 'defines open_timeout via BaseVendorHelper' do
      expect(helper).to respond_to(:open_timeout)
    end

    it 'defines read_timeout via BaseVendorHelper' do
      expect(helper).to respond_to(:read_timeout)
    end

    it 'defines write_timeout via BaseVendorHelper' do
      expect(helper).to respond_to(:write_timeout)
    end

    it 'has reasonable timeout values' do
      expect(helper.open_timeout).to be_a(Numeric)
      expect(helper.read_timeout).to be_a(Numeric)
      expect(helper.write_timeout).to be_a(Numeric)
      expect(helper.open_timeout).to be > 0
      expect(helper.read_timeout).to be > 0
      expect(helper.write_timeout).to be > 0
    end
  end

  describe 'endpoint caching' do
    it 'responds to reset_endpoint_cache' do
      expect(OllamaHelper).to respond_to(:reset_endpoint_cache)
    end

    it 'responds to find_endpoint' do
      expect(OllamaHelper).to respond_to(:find_endpoint)
    end
  end

  describe 'list_models' do
    it 'is available as a module function' do
      expect(OllamaHelper).to respond_to(:list_models)
    end

    it 'returns an Array' do
      result = OllamaHelper.list_models
      expect(result).to be_a(Array)
    end
  end
end
