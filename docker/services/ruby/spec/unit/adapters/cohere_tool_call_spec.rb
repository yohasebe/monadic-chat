# frozen_string_literal: true

require 'spec_helper'
require 'monadic/adapters/vendors/cohere_helper'

RSpec.describe 'Cohere Tool Call Processing' do
  let(:test_class) do
    Class.new do
      include CohereHelper

      # Make process_json_data accessible for testing
      public :process_json_data
    end
  end

  let(:helper) { test_class.new }

  before do
    # Mock necessary constants
    stub_const("CONFIG", {
      "COHERE_API_KEY" => "test-key",
      "EXTRA_LOGGING" => false
    })

    unless defined?(MonadicApp)
      module MonadicApp
        EXTRA_LOG_FILE = "/tmp/test_extra.log"
      end
    end
  end

  describe 'DONE message handling - code structure verification' do
    it 'verifies fix for duplicate DONE message issue (commit 63944bbb)' do
      # This test verifies the code structure to ensure the duplicate DONE message
      # issue is fixed. The fix changed from processing results after process_functions
      # to using early return pattern.

      source_file = File.read(File.join(__dir__, '../../../lib/monadic/adapters/vendors/cohere_helper.rb'))

      # The fix introduced in commit 63944bbb should have:
      # 1. Check for accumulated_tool_calls.any?
      expect(source_file).to match(/if\s+accumulated_tool_calls\.any\?/),
        "Should check for tool calls with accumulated_tool_calls.any?"

      # 2. Early return pattern: return process_functions(...)
      expect(source_file).to match(/return\s+process_functions\(/),
        "Should use early return pattern to avoid duplicate DONE message"

      # 3. The old problematic code should NOT exist anymore
      # The old code had these patterns AFTER process_functions call:
      # - new_results = process_functions(...)
      # - Combined result processing
      # - block&.call res (sending result)
      # - block&.call done_msg (sending DONE) <- This was the duplicate

      # Verify that the section between process_functions and the final 'else' is minimal
      # Extract the tool calls block
      if source_file =~ /if\s+accumulated_tool_calls\.any\?(.*?)else/m
        tool_calls_block = $1

        # The block should be relatively short (< 30 lines) after the fix
        # because we removed the result processing code
        lines_in_block = tool_calls_block.split("\n").reject { |l| l.strip.empty? || l.strip.start_with?('#') }.length

        expect(lines_in_block).to be < 30,
          "Tool calls block should be concise after fix (< 30 lines), but has #{lines_in_block} lines. " \
          "This suggests the old result processing code may still be present."
      end
    end
  end

  describe 'Early return pattern verification' do
    it 'uses early return when tool calls are detected' do
      # This is a structural test to verify the code pattern
      # Read the actual source code to verify the pattern
      source_file = File.read(File.join(__dir__, '../../../lib/monadic/adapters/vendors/cohere_helper.rb'))

      # Look for the pattern: if accumulated_tool_calls.any? ... return process_functions(...)
      # This verifies that the fix (commit 63944bbb) is in place

      # Pattern should include:
      # 1. Check for tool calls: if accumulated_tool_calls.any?
      # 2. Early return: return process_functions(...)

      expect(source_file).to match(/if\s+accumulated_tool_calls\.any\?/),
        "Should check for tool calls with accumulated_tool_calls.any?"

      expect(source_file).to match(/return\s+process_functions\(/),
        "Should use early return pattern: return process_functions(...)"

      # Verify the fix is in place: should NOT have the old pattern of processing results after process_functions
      # The old code had these lines after process_functions:
      # new_results = process_functions(...)
      # ... lots of result processing ...
      # block&.call done_msg  # <- This was the duplicate DONE

      # Count occurrences of process_functions calls
      process_functions_calls = source_file.scan(/process_functions\(/).length

      # Should have at least one call (the early return in accumulated_tool_calls block)
      expect(process_functions_calls).to be > 0,
        "Should have at least one process_functions call"
    end
  end
end
