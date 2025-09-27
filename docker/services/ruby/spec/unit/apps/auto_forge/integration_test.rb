#!/usr/bin/env ruby
# frozen_string_literal: true

# Integration test for AutoForge with GPT-5-Codex
# Tests proper agent integration, Unicode handling, and real HTML generation

require 'json'
require 'fileutils'
require 'pathname'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require_relative 'auto_forge'
require_relative 'auto_forge_utils'
require_relative '../../lib/monadic/agents/gpt5_codex_agent'

# Define a stub MonadicHelper for standalone testing
module MonadicHelper
  def monadic_helper_available?
    true
  end
end

class AutoForgeIntegrationTest
  include MonadicHelper
  include Monadic::Agents::GPT5CodexAgent

  def initialize
    @context = {
      openai_api_key: ENV['OPENAI_API_KEY'],
      app_instance: self
    }
    @test_results = []
  end

  def run_tests
    puts "\n=== AutoForge Integration Tests ==="
    puts "Testing GPT-5-Codex integration and functionality\n\n"

    # Test 1: Unicode/Japanese project name handling
    test_unicode_project_names

    # Test 2: GPT-5-Codex agent pattern verification
    test_agent_pattern

    # Test 3: Real HTML generation (not placeholders)
    test_real_html_generation

    # Test 4: Project modification capability
    test_project_modification

    # Print summary
    print_test_summary
  end

  private

  def test_unicode_project_names
    puts "Test 1: Unicode/Japanese Project Name Handling"
    puts "=" * 50

    test_names = [
      { input: "病気診断アプリ", expected_contains: "病気診断アプリ" },
      { input: "天気予報アプリ", expected_contains: "天気予報アプリ" },
      { input: "ToDo管理アプリ", expected_contains: "ToDo管理アプリ" },
      { input: "中文测试应用", expected_contains: "中文测试应用" },
      { input: "앱 테스트", expected_contains: "앱 테스트" }
    ]

    test_names.each do |test|
      begin
        result = AutoForgeUtils.create_project_directory(test[:input])
        dir_name = result[:name]

        if dir_name.include?(test[:expected_contains])
          puts "  ✅ '#{test[:input]}' → '#{dir_name}' (preserves Unicode)"
          @test_results << { test: "Unicode: #{test[:input]}", passed: true }
        else
          puts "  ❌ '#{test[:input]}' → '#{dir_name}' (lost Unicode characters)"
          @test_results << { test: "Unicode: #{test[:input]}", passed: false }
        end

        # Cleanup test directory
        FileUtils.rm_rf(result[:path]) if result[:path] && File.exist?(result[:path])
      rescue => e
        puts "  ❌ Error testing '#{test[:input]}': #{e.message}"
        @test_results << { test: "Unicode: #{test[:input]}", passed: false }
      end
    end
    puts
  end

  def test_agent_pattern
    puts "Test 2: GPT-5-Codex Agent Pattern Verification"
    puts "=" * 50

    # Verify module inclusion
    if self.class.included_modules.include?(Monadic::Agents::GPT5CodexAgent)
      puts "  ✅ GPT5CodexAgent module included"
      @test_results << { test: "Agent module inclusion", passed: true }
    else
      puts "  ❌ GPT5CodexAgent module not included"
      @test_results << { test: "Agent module inclusion", passed: false }
    end

    # Verify method availability
    if respond_to?(:call_gpt5_codex)
      puts "  ✅ call_gpt5_codex method available"
      @test_results << { test: "call_gpt5_codex method", passed: true }
    else
      puts "  ❌ call_gpt5_codex method not available"
      @test_results << { test: "call_gpt5_codex method", passed: false }
    end

    # Test context passing to HtmlGenerator
    generator = AutoForge::Agents::HtmlGenerator.new(@context)
    if generator.instance_variable_get(:@context)[:app_instance] == self
      puts "  ✅ Context properly passed to HtmlGenerator"
      @test_results << { test: "Context passing", passed: true }
    else
      puts "  ❌ Context not properly passed to HtmlGenerator"
      @test_results << { test: "Context passing", passed: false }
    end

    puts
  end

  def test_real_html_generation
    puts "Test 3: Real HTML Generation (No Placeholders)"
    puts "=" * 50

    # Skip if no API key
    if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'].empty?
      puts "  ⚠️  Skipping: OPENAI_API_KEY not set"
      @test_results << { test: "HTML generation", passed: nil, skipped: true }
      puts
      return
    end

    spec = {
      'name' => 'TestCalculator',
      'type' => 'calculator',
      'description' => 'A simple calculator with basic operations',
      'features' => ['Addition', 'Subtraction', 'Multiplication', 'Division']
    }

    puts "  Testing with spec: #{spec['name']}"

    # Create a mock generate_application call
    generator = AutoForge::Agents::HtmlGenerator.new(@context)
    prompt = "Create a simple calculator with buttons for digits 0-9 and operations +, -, *, /. Include a display for the result."

    result = generator.generate(prompt)

    if result.nil?
      puts "  ❌ Generator returned nil"
      @test_results << { test: "HTML generation", passed: false }
    elsif result[:content] && result[:content].include?("<!DOCTYPE html>")
      # Check for placeholders
      if result[:content].include?("Generated from:") ||
         result[:content].include?("Mock HTML") ||
         result[:content].include?("<!-- Placeholder")
        puts "  ❌ Generated HTML contains placeholders"
        puts "  First 200 chars: #{result[:content][0..200]}"
        @test_results << { test: "HTML generation", passed: false }
      else
        puts "  ✅ Generated real HTML (#{result[:content].length} chars)"
        puts "  Contains: DOCTYPE ✓, <html> ✓, No placeholders ✓"
        @test_results << { test: "HTML generation", passed: true }
      end
    else
      puts "  ❌ Generated content doesn't look like HTML"
      puts "  Content type: #{result[:mode]}"
      @test_results << { test: "HTML generation", passed: false }
    end

    puts
  end

  def test_project_modification
    puts "Test 4: Project Modification Capability"
    puts "=" * 50

    # Test StateManager module presence
    begin
      require_relative 'utils/state_manager'

      # Create a project state
      test_id = "test_#{Time.now.to_i}"
      AutoForge::Utils::StateManager.init_state(test_id)

      if AutoForge::Utils::StateManager.get_state(test_id)
        puts "  ✅ StateManager initialized and state created"
        @test_results << { test: "StateManager init", passed: true }
      else
        puts "  ❌ StateManager state creation failed"
        @test_results << { test: "StateManager init", passed: false }
      end

      # Test execution tracking
      AutoForge::Utils::StateManager.lock_generation(test_id)
      if AutoForge::Utils::StateManager.generation_locked?(test_id)
        puts "  ✅ Execution locking works"
        @test_results << { test: "Execution locking", passed: true }
      else
        puts "  ❌ Execution locking failed"
        @test_results << { test: "Execution locking", passed: false }
      end

      # Test unlock
      AutoForge::Utils::StateManager.unlock_generation(test_id)
      if !AutoForge::Utils::StateManager.generation_locked?(test_id)
        puts "  ✅ Execution unlocking works"
        @test_results << { test: "Execution unlocking", passed: true }
      else
        puts "  ❌ Execution unlocking failed"
        @test_results << { test: "Execution unlocking", passed: false }
      end

      # Cleanup
      AutoForge::Utils::StateManager.cleanup(test_id)
    rescue => e
      puts "  ❌ StateManager error: #{e.message}"
      @test_results << { test: "StateManager", passed: false }
    end

    puts
  end

  def print_test_summary
    puts "=" * 50
    puts "Test Summary"
    puts "=" * 50

    passed = @test_results.count { |r| r[:passed] == true }
    failed = @test_results.count { |r| r[:passed] == false }
    skipped = @test_results.count { |r| r[:skipped] == true }

    @test_results.each do |result|
      status = if result[:skipped]
                 "⚠️  SKIPPED"
               elsif result[:passed]
                 "✅ PASS"
               else
                 "❌ FAIL"
               end
      puts "  #{status}: #{result[:test]}"
    end

    puts "\nTotal: #{passed} passed, #{failed} failed, #{skipped} skipped"

    if failed == 0 && skipped == 0
      puts "\n🎉 All tests passed!"
    elsif failed == 0
      puts "\n✅ All active tests passed (#{skipped} skipped)"
    else
      puts "\n⚠️  Some tests failed - review implementation"
    end
  end
end

# Run tests if executed directly
if __FILE__ == $0
  tester = AutoForgeIntegrationTest.new
  tester.run_tests
end