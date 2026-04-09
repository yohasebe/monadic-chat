# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'

# Mock SeleniumHelper to avoid requiring the full dependency chain
module Monadic
  module Utils
    module SeleniumHelper
      def check_selenium_or_error
        nil # No error by default
      end

      def send_command(command:, container:)
        "{}"
      end
    end
  end
end

require_relative '../../../apps/auto_forge/auto_forge_debugger'

RSpec.describe AutoForge::Debugger do
  subject(:debugger) { described_class.new }

  describe '#format_debug_results' do
    it 'stores screenshot filename when present (no _image vision injection)' do
      result = {
        'success' => true,
        'javascript_errors' => [],
        'warnings' => [],
        'functionality_tests' => [],
        'performance' => { 'loadTime' => 500 },
        'screenshot' => 'autoforge_debug_1234567890.png',
        'viewport' => { 'width' => 1280, 'height' => 900 }
      }

      formatted = debugger.send(:format_debug_results, result)

      expect(formatted[:success]).to be true
      expect(formatted[:screenshot]).to eq('autoforge_debug_1234567890.png')
      expect(formatted[:_image]).to be_nil
    end

    it 'does not include screenshot when not present' do
      result = {
        'success' => true,
        'javascript_errors' => [],
        'warnings' => [],
        'functionality_tests' => [],
        'performance' => {}
      }

      formatted = debugger.send(:format_debug_results, result)

      expect(formatted[:_image]).to be_nil
      expect(formatted[:screenshot]).to be_nil
    end

    it 'includes summary with success status' do
      result = {
        'success' => true,
        'javascript_errors' => [],
        'warnings' => [],
        'functionality_tests' => [
          { 'test' => 'Page loads', 'passed' => true }
        ],
        'performance' => { 'loadTime' => 200 }
      }

      formatted = debugger.send(:format_debug_results, result)

      expect(formatted[:summary]).to include('✅ Page loaded successfully')
      expect(formatted[:summary]).to include('✅ No JavaScript errors detected')
    end

    it 'reports JavaScript errors in summary' do
      result = {
        'success' => true,
        'javascript_errors' => [
          { 'message' => 'TypeError: undefined is not a function', 'timestamp' => 12345 }
        ],
        'warnings' => [],
        'functionality_tests' => []
      }

      formatted = debugger.send(:format_debug_results, result)

      expect(formatted[:javascript_errors].length).to eq(1)
      expect(formatted[:summary]).to include('⚠️  Found 1 JavaScript error(s)')
    end

    it 'filters WebDriver log warnings' do
      result = {
        'success' => true,
        'javascript_errors' => [],
        'warnings' => [
          { 'message' => "'WebDriver' object has no attribute 'get_log'", 'timestamp' => 12345 },
          { 'message' => 'Deprecation warning: something', 'timestamp' => 12346 }
        ],
        'functionality_tests' => []
      }

      formatted = debugger.send(:format_debug_results, result)

      expect(formatted[:warnings].length).to eq(1)
      expect(formatted[:warnings].first['message']).to include('Deprecation')
    end

    it 'returns error hash when result is nil' do
      formatted = debugger.send(:format_debug_results, nil)

      expect(formatted[:success]).to be false
      expect(formatted[:error]).to eq('No debug results')
    end
  end
end
