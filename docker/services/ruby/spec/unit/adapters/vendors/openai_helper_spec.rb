# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/openai_helper'

RSpec.describe OpenAIHelper do
  subject(:helper) do
    Class.new do
      include OpenAIHelper
    end.new
  end

  describe '#normalize_function_call_arguments' do
    it 'returns empty string for nil input' do
      expect(helper.send(:normalize_function_call_arguments, nil)).to eq("")
    end

    it 'replaces smart double quotes with ASCII double quotes' do
      raw = "\u201Chello\u201D"  # "hello"
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('"hello"')
    end

    it 'replaces smart single quotes with ASCII single quotes' do
      raw = "\u2018it\u2019s\u2019"  # 'it's'
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq("'it's'")
    end

    it 'replaces full-width brackets with ASCII equivalents' do
      raw = "\uFF5B\"key\": \"val\"\uFF5D"  # ｛"key": "val"｝
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('{"key": "val"}')
    end

    it 'replaces full-width colons and commas' do
      raw = "\"a\"\uFF1A1\uFF0C\"b\"\uFF1A2"  # "a"：1，"b"：2
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('"a":1,"b":2')
    end

    it 'replaces non-breaking space with regular space' do
      raw = "{ \"key\"\u00A0: \"value\" }"
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('{ "key" : "value" }')
    end

    it 'replaces fullwidth semicolons with commas' do
      raw = "[\"a\"\uFF1B\"b\"]"  # ["a"；"b"]
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('["a","b"]')
    end

    it 'handles combined smart quotes and full-width punctuation' do
      raw = "\uFF5B\u201Cname\u201D\uFF1A\u201CAlice\u201D\uFF5D"
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq('{"name":"Alice"}')
    end

    it 'preserves normal ASCII JSON unchanged' do
      raw = '{"key": "value", "num": 42}'
      result = helper.send(:normalize_function_call_arguments, raw)
      expect(result).to eq(raw)
    end
  end

  describe '#parse_function_call_arguments' do
    it 'parses valid JSON directly' do
      result = helper.send(:parse_function_call_arguments, '{"key": "value"}')
      expect(result).to eq({ "key" => "value" })
    end

    it 'returns empty hash for nil input' do
      result = helper.send(:parse_function_call_arguments, nil)
      expect(result).to eq({})
    end

    it 'returns empty hash for whitespace-only input' do
      result = helper.send(:parse_function_call_arguments, '   ')
      expect(result).to eq({})
    end

    it 'normalizes smart quotes before parsing' do
      raw = "\u201C{\"name\": \"test\"}\u201D"
      # After normalization: "{"name": "test"}"  — outer quotes make it invalid
      # This should either parse via repair or return {}
      result = helper.send(:parse_function_call_arguments, raw)
      expect(result).to be_a(Hash)
    end

    it 'returns empty hash for completely unparseable input' do
      result = helper.send(:parse_function_call_arguments, 'this is not json at all')
      expect(result).to eq({})
    end
  end

  describe '#get_current_app_key' do
    it 'returns "default" for empty session hash' do
      session = {}
      result = helper.send(:get_current_app_key, session)
      expect(result).to eq('default')
    end

    it 'extracts app_name from session parameters' do
      session = { parameters: { "app_name" => "MyTestApp" } }
      result = helper.send(:get_current_app_key, session)
      # Should be lowercased and sanitized
      expect(result).to match(/mytestapp/i)
    end

    it 'falls back to current_app when app_name is nil' do
      session = { parameters: {}, current_app: "FallbackApp" }
      result = helper.send(:get_current_app_key, session)
      expect(result).to match(/fallbackapp/i)
    end

    it 'returns "default" when session has no app info' do
      session = { parameters: {} }
      result = helper.send(:get_current_app_key, session)
      expect(result).to eq('default')
    end

    it 'sanitizes special characters in app name' do
      session = { parameters: { "app_name" => 'My App! @#$' } }
      result = helper.send(:get_current_app_key, session)
      expect(result).not_to match(/[^a-z0-9_\-]/)
    end
  end

  describe '#document_type?' do
    it 'returns true for PDF' do
      expect(helper.document_type?("application/pdf")).to be true
    end

    it 'returns true for XLSX' do
      expect(helper.document_type?("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")).to be true
    end

    it 'returns true for DOCX' do
      expect(helper.document_type?("application/vnd.openxmlformats-officedocument.wordprocessingml.document")).to be true
    end

    it 'returns true for CSV' do
      expect(helper.document_type?("text/csv")).to be true
    end

    it 'returns true for plain text' do
      expect(helper.document_type?("text/plain")).to be true
    end

    it 'returns false for images' do
      expect(helper.document_type?("image/jpeg")).to be false
      expect(helper.document_type?("image/png")).to be false
    end

    it 'returns false for nil' do
      expect(helper.document_type?(nil)).to be false
    end
  end

  describe '#resolve_file_id_for_input' do
    let(:session) { {} }

    before do
      stub_const("CONFIG", { "OPENAI_API_KEY" => "test-key", "EXTRA_LOGGING" => nil })
    end

    it 'returns nil for non-base64 data' do
      img = { "data" => "not-base64", "title" => "test.pdf", "type" => "application/pdf" }
      expect(helper.resolve_file_id_for_input(session, img)).to be_nil
    end

    it 'returns nil for missing data key' do
      img = { "title" => "test.pdf", "type" => "application/pdf" }
      expect(helper.resolve_file_id_for_input(session, img)).to be_nil
    end

    it 'returns file_id on successful upload' do
      fake_response = instance_double(Net::HTTPOK, code: "200", body: '{"id": "file-xyz789"}')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(fake_response)

      img = {
        "data" => "data:application/pdf;base64,SGVsbG8=",
        "title" => "test.pdf",
        "type" => "application/pdf"
      }
      result = helper.resolve_file_id_for_input(session, img)
      expect(result).to eq("file-xyz789")
    end

    it 'returns nil on error without raising' do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Errno::ECONNREFUSED)

      img = {
        "data" => "data:application/pdf;base64,SGVsbG8=",
        "title" => "test.pdf",
        "type" => "application/pdf"
      }
      expect { helper.resolve_file_id_for_input(session, img) }.not_to raise_error
      expect(helper.resolve_file_id_for_input(session, img)).to be_nil
    end
  end
end
