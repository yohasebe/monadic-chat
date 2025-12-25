# frozen_string_literal: true

require 'json'
require 'fileutils'

# Provider Matrix Test Reporter
#
# Generates comprehensive reports for Provider Matrix test results.
# Outputs JSON summary and Markdown coverage reports.
#
# Usage:
#   reporter = ProviderMatrixReporter.new(output_dir: 'tmp/test_results')
#   reporter.record_result(provider: 'openai', app: 'ChatOpenAI', passed: true, duration: 1.5)
#   reporter.finalize
#
module ProviderMatrixReporter
  class Reporter
    attr_reader :results, :start_time, :output_dir

    def initialize(output_dir: nil)
      @output_dir = output_dir || default_output_dir
      @results = []
      @start_time = Time.now
      @providers = Set.new
      @apps = Set.new
      FileUtils.mkdir_p(@output_dir)
    end

    # Record a single test result
    def record_result(provider:, app:, passed:, duration: nil, error: nil, tool_calls: nil, skipped: false, skip_reason: nil)
      @providers.add(provider)
      @apps.add(app)

      @results << {
        provider: provider,
        app: app,
        passed: passed,
        skipped: skipped,
        skip_reason: skip_reason,
        duration: duration&.round(2),
        error: error,
        tool_calls: tool_calls,
        timestamp: Time.now.iso8601
      }
    end

    # Generate all reports
    def finalize
      end_time = Time.now
      total_duration = (end_time - @start_time).round(2)

      summary = generate_summary(total_duration)

      # Write JSON report
      write_json_report(summary)

      # Write Markdown reports
      write_coverage_report(summary)
      write_detailed_report(summary)

      # Print summary to console
      print_console_summary(summary)

      summary
    end

    private

    def default_output_dir
      File.expand_path('../../../tmp/test_results', __dir__)
    end

    def generate_summary(total_duration)
      passed = @results.count { |r| r[:passed] && !r[:skipped] }
      failed = @results.count { |r| !r[:passed] && !r[:skipped] }
      skipped = @results.count { |r| r[:skipped] }
      total = @results.count { |r| !r[:skipped] }

      # Group by provider
      by_provider = @results.group_by { |r| r[:provider] }
      provider_stats = by_provider.transform_values do |results|
        {
          total: results.count { |r| !r[:skipped] },
          passed: results.count { |r| r[:passed] && !r[:skipped] },
          failed: results.count { |r| !r[:passed] && !r[:skipped] },
          skipped: results.count { |r| r[:skipped] }
        }
      end

      # Group by app (base name)
      by_app = @results.group_by { |r| extract_base_app(r[:app]) }
      app_stats = by_app.transform_values do |results|
        {
          providers_tested: results.map { |r| r[:provider] }.uniq,
          passed: results.count { |r| r[:passed] && !r[:skipped] },
          failed: results.count { |r| !r[:passed] && !r[:skipped] }
        }
      end

      {
        run_id: ENV['SUMMARY_RUN_ID'] || Time.now.strftime('%Y%m%d_%H%M%S'),
        timestamp: Time.now.iso8601,
        duration_seconds: total_duration,
        summary: {
          total: total,
          passed: passed,
          failed: failed,
          skipped: skipped,
          pass_rate: total > 0 ? (passed.to_f / total * 100).round(1) : 0
        },
        providers: provider_stats,
        apps: app_stats,
        failures: @results.select { |r| !r[:passed] && !r[:skipped] },
        results: @results
      }
    end

    def extract_base_app(app_name)
      # Remove provider suffix (OpenAI, Claude, Gemini, etc.)
      app_name.sub(/(OpenAI|Claude|Gemini|Grok|Mistral|Cohere|DeepSeek|Perplexity|Ollama)$/, '')
    end

    def write_json_report(summary)
      filename = File.join(@output_dir, "matrix_#{summary[:run_id]}.json")
      File.write(filename, JSON.pretty_generate(summary))
      puts "  📄 JSON report: #{filename}"
    end

    def write_coverage_report(summary)
      filename = File.join(@output_dir, "matrix_coverage_#{summary[:run_id]}.md")

      content = <<~MD
        # Provider Matrix Coverage Report

        **Run ID:** #{summary[:run_id]}
        **Date:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
        **Duration:** #{summary[:duration_seconds]}s

        ## Summary

        | Metric | Count |
        |--------|-------|
        | Total Tests | #{summary[:summary][:total]} |
        | Passed | #{summary[:summary][:passed]} |
        | Failed | #{summary[:summary][:failed]} |
        | Skipped | #{summary[:summary][:skipped]} |
        | Pass Rate | #{summary[:summary][:pass_rate]}% |

        ## Provider Coverage

        | Provider | Total | Passed | Failed | Skipped | Status |
        |----------|-------|--------|--------|---------|--------|
      MD

      summary[:providers].each do |provider, stats|
        status = stats[:failed] == 0 ? '✅' : '❌'
        content += "| #{provider} | #{stats[:total]} | #{stats[:passed]} | #{stats[:failed]} | #{stats[:skipped]} | #{status} |\n"
      end

      content += <<~MD

        ## App Coverage

        | App | Providers Tested | Passed | Failed | Status |
        |-----|------------------|--------|--------|--------|
      MD

      summary[:apps].each do |app, stats|
        status = stats[:failed] == 0 ? '✅' : '❌'
        providers = stats[:providers_tested].join(', ')
        content += "| #{app} | #{providers} | #{stats[:passed]} | #{stats[:failed]} | #{status} |\n"
      end

      File.write(filename, content)
      puts "  📊 Coverage report: #{filename}"
    end

    def write_detailed_report(summary)
      return if summary[:failures].empty?

      filename = File.join(@output_dir, "matrix_failures_#{summary[:run_id]}.md")

      content = <<~MD
        # Provider Matrix Failure Report

        **Run ID:** #{summary[:run_id]}
        **Date:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
        **Failed Tests:** #{summary[:failures].count}

        ## Failures

      MD

      summary[:failures].each_with_index do |failure, idx|
        content += <<~MD
          ### #{idx + 1}. #{failure[:app]} (#{failure[:provider]})

          - **Error:** #{failure[:error] || 'Unknown error'}
          - **Duration:** #{failure[:duration]}s

        MD
      end

      File.write(filename, content)
      puts "  ❌ Failure report: #{filename}"
    end

    def print_console_summary(summary)
      puts "\n" + "=" * 60
      puts "Provider Matrix Test Summary"
      puts "=" * 60
      puts "Run ID: #{summary[:run_id]}"
      puts "Duration: #{summary[:duration_seconds]}s"
      puts ""
      puts "Results:"
      puts "  Total:   #{summary[:summary][:total]}"
      puts "  Passed:  #{summary[:summary][:passed]} ✅"
      puts "  Failed:  #{summary[:summary][:failed]} #{summary[:summary][:failed] > 0 ? '❌' : ''}"
      puts "  Skipped: #{summary[:summary][:skipped]}"
      puts "  Pass Rate: #{summary[:summary][:pass_rate]}%"
      puts ""
      puts "Provider Breakdown:"
      summary[:providers].each do |provider, stats|
        status = stats[:failed] == 0 ? '✅' : '❌'
        puts "  #{provider.ljust(12)} #{stats[:passed]}/#{stats[:total]} #{status}"
      end
      puts "=" * 60
    end
  end

  # RSpec formatter integration
  class RSpecFormatter
    RSpec::Core::Formatters.register self, :example_passed, :example_failed, :example_pending, :close

    def initialize(output)
      @output = output
      @reporter = Reporter.new
    end

    def example_passed(notification)
      record_example(notification.example, passed: true)
    end

    def example_failed(notification)
      record_example(notification.example, passed: false, error: notification.example.exception&.message)
    end

    def example_pending(notification)
      record_example(notification.example, passed: false, skipped: true, skip_reason: notification.example.execution_result.pending_message)
    end

    def close(_notification)
      @reporter.finalize
    end

    private

    def record_example(example, passed:, error: nil, skipped: false, skip_reason: nil)
      # Extract provider and app from example metadata or description
      metadata = example.metadata
      description = example.full_description

      # Try to extract provider from context
      provider = extract_provider(description, metadata)
      app = extract_app(description, metadata)

      return unless provider && app

      @reporter.record_result(
        provider: provider,
        app: app,
        passed: passed,
        duration: example.execution_result.run_time,
        error: error,
        skipped: skipped,
        skip_reason: skip_reason
      )
    end

    def extract_provider(description, metadata)
      # Match patterns like "with openai provider" or "OpenAI"
      if description =~ /with (\w+) provider/i
        $1.downcase
      elsif metadata[:provider]
        metadata[:provider]
      end
    end

    def extract_app(description, metadata)
      # Match patterns like "ChatOpenAI returns" or app names
      if description =~ /(\w+(?:OpenAI|Claude|Gemini|Grok|Mistral|Cohere|DeepSeek|Perplexity|Ollama))/
        $1
      elsif metadata[:app]
        metadata[:app]
      end
    end
  end
end
