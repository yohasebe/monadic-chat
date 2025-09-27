#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative 'auto_forge'

# Mock HTML generator for testing
module AutoForge
  module Agents
    class HtmlGenerator
      def initialize(context)
        @context = context
      end

      def generate(prompt, existing_content: nil, file_name: nil)
        # Return mock HTML for testing
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
              <title>Test App</title>
          </head>
          <body>
              <h1>Generated from: #{prompt[0..50]}...</h1>
          </body>
          </html>
        HTML
      end
    end
  end
end

class OrchestratorTest < Minitest::Test
  def setup
    @app = AutoForge::App.new
  end

  def test_repeated_generation_updates_existing_project
    spec = {
      name: "calculator",
      type: "utility",
      description: "Test calculator",
      features: ["Basic math", "Scientific functions"]
    }

    result1 = @app.generate_application(spec)
    assert result1[:success], "First execution should succeed: #{result1[:error] || result1[:details]&.join(', ')}"
    assert result1[:project_path]

    result2 = @app.generate_application(spec)
    assert result2[:success], "Second execution should also succeed"
    assert_equal result1[:project_path], result2[:project_path], "Project path should remain the same"

    # Cleanup
    FileUtils.rm_rf(result1[:project_path]) if result1[:project_path]
  end

  def test_create_simple_app
    result = @app.create_simple_app("timer", "A countdown timer", ["Start/Stop", "Reset"])

    assert result[:success]
    assert result[:files_created].include?("index.html")

    # Cleanup
    FileUtils.rm_rf(result[:project_path]) if result[:project_path]
  end
end

puts "\n=== Running Orchestrator Tests ==="