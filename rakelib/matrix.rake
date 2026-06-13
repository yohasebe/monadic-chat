# frozen_string_literal: true

# =============================================================================
# Provider Matrix Tests
# =============================================================================
# Comprehensive tests for all AI providers × all apps
# Tool calls are intercepted - no actual API costs for media generation
#
# Usage:
#   rake matrix                           # Run with all configured providers
#   rake matrix[openai,anthropic]         # Run with specific providers
#   rake matrix:report                    # View latest test report
#
# Environment variables:
#   PROVIDERS=openai,anthropic   # Comma-separated list of providers to test
#   DEBUG=true                   # Enable debug output
# =============================================================================

desc "Run Provider Matrix tests. Usage: rake matrix[providers] (e.g., rake matrix[openai,anthropic])"
task :matrix, [:providers] do |_t, args|
  ENV['RUN_API'] = 'true'
  ENV['API_TIMEOUT'] ||= '90'
  ENV['API_MAX_RETRIES'] ||= '0'
  ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')

  # Set providers from argument or environment
  if args[:providers]
    ENV['PROVIDERS'] = args[:providers]
  end

  providers = ENV['PROVIDERS'] || 'all configured'
  puts "\n" + "=" * 60
  puts "Provider Matrix Tests"
  puts "=" * 60
  puts "Providers: #{providers}"
  puts "Run ID: #{ENV['SUMMARY_RUN_ID']}"
  puts "=" * 60 + "\n"

  Dir.chdir("docker/services/ruby") do
    dir = 'spec/integration/provider_matrix'
    if Dir.exist?(dir) && !Dir.glob(File.join(dir, '**', '*_spec.rb')).empty?
      fmt = '--format documentation'
      # Add JSON output for reporting
      json_out = "tmp/test_results/matrix_rspec_#{ENV['SUMMARY_RUN_ID']}.json"
      FileUtils.mkdir_p('tmp/test_results')
      sh "bundle exec rspec #{dir} #{fmt} --format json --out #{json_out}"

      # Generate coverage report from JSON
      generate_matrix_report(json_out, ENV['SUMMARY_RUN_ID'])
    else
      puts "❌ Matrix specs not found in #{dir}"
      exit 1
    end
  end
end

namespace :matrix do
  desc "View latest Provider Matrix test report"
  task :report do
    Dir.chdir("docker/services/ruby") do
      reports = Dir.glob('tmp/test_results/matrix_coverage_*.md').sort.reverse
      if reports.empty?
        puts "No matrix reports found. Run 'rake matrix' first."
      else
        latest = reports.first
        puts "\n📊 Latest Report: #{latest}\n\n"
        puts File.read(latest)
      end
    end
  end

  desc "List all Provider Matrix test reports"
  task :history do
    Dir.chdir("docker/services/ruby") do
      reports = Dir.glob('tmp/test_results/matrix_*.md').sort.reverse
      if reports.empty?
        puts "No matrix reports found."
      else
        puts "\n📁 Available Reports:\n"
        reports.each_with_index do |r, i|
          puts "  #{i + 1}. #{File.basename(r)}"
        end
      end
    end
  end

  desc "Clean up old Provider Matrix reports (keeps latest 5)"
  task :cleanup, [:keep] do |_t, args|
    keep = (args[:keep] || 5).to_i
    Dir.chdir("docker/services/ruby") do
      %w[matrix_*.json matrix_*.md].each do |pattern|
        files = Dir.glob("tmp/test_results/#{pattern}").sort.reverse
        files[keep..].each do |f|
          puts "Removing: #{f}"
          File.delete(f)
        end
      end
      puts "✅ Cleanup complete (kept latest #{keep})"
    end
  end
end

# Helper method to generate matrix report from RSpec JSON output
def generate_matrix_report(json_file, run_id)
  return unless File.exist?(json_file)

  require 'json'
  data = JSON.parse(File.read(json_file))

  # Parse results
  providers = {}
  apps = {}
  failures = []

  data['examples'].each do |ex|
    # Extract provider and app from description
    desc = ex['full_description'] || ''

    provider = nil
    app = nil

    if desc =~ /with (\w+) provider/i
      provider = $1.downcase
    end

    if desc =~ /(\w+(?:OpenAI|Claude|Gemini|Grok|Mistral|Cohere|DeepSeek|Ollama))/
      app = $1
    end

    next unless provider && app

    # Track provider stats
    providers[provider] ||= { total: 0, passed: 0, failed: 0, pending: 0 }
    providers[provider][:total] += 1

    case ex['status']
    when 'passed'
      providers[provider][:passed] += 1
    when 'failed'
      providers[provider][:failed] += 1
      failures << { provider: provider, app: app, error: ex.dig('exception', 'message') }
    when 'pending'
      providers[provider][:pending] += 1
    end

    # Track app stats
    base_app = app.sub(/(OpenAI|Claude|Gemini|Grok|Mistral|Cohere|DeepSeek|Ollama)$/, '')
    apps[base_app] ||= { providers: Set.new, passed: 0, failed: 0 }
    apps[base_app][:providers].add(provider)
    apps[base_app][:passed] += 1 if ex['status'] == 'passed'
    apps[base_app][:failed] += 1 if ex['status'] == 'failed'
  end

  # Generate markdown report
  total_passed = providers.values.sum { |p| p[:passed] }
  total_failed = providers.values.sum { |p| p[:failed] }
  total = providers.values.sum { |p| p[:total] }
  pass_rate = total > 0 ? (total_passed.to_f / total * 100).round(1) : 0

  report = <<~MD
    # Provider Matrix Coverage Report

    **Run ID:** #{run_id}
    **Date:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
    **Duration:** #{data['summary']['duration'].round(2)}s

    ## Summary

    | Metric | Count |
    |--------|-------|
    | Total Tests | #{total} |
    | Passed | #{total_passed} |
    | Failed | #{total_failed} |
    | Pass Rate | #{pass_rate}% |

    ## Provider Coverage

    | Provider | Total | Passed | Failed | Status |
    |----------|-------|--------|--------|--------|
  MD

  providers.each do |provider, stats|
    status = stats[:failed] == 0 ? '✅' : '❌'
    report += "| #{provider} | #{stats[:total]} | #{stats[:passed]} | #{stats[:failed]} | #{status} |\n"
  end

  report += <<~MD

    ## App Coverage

    | App | Providers Tested | Passed | Failed | Status |
    |-----|------------------|--------|--------|--------|
  MD

  apps.each do |app, stats|
    status = stats[:failed] == 0 ? '✅' : '❌'
    providers_list = stats[:providers].to_a.join(', ')
    report += "| #{app} | #{providers_list} | #{stats[:passed]} | #{stats[:failed]} | #{status} |\n"
  end

  # Write report
  report_file = "tmp/test_results/matrix_coverage_#{run_id}.md"
  File.write(report_file, report)
  puts "\n📊 Coverage report: #{report_file}"

  # Write failures if any
  if failures.any?
    failure_report = <<~MD
      # Provider Matrix Failure Report

      **Run ID:** #{run_id}
      **Failed Tests:** #{failures.count}

      ## Failures

    MD

    failures.each_with_index do |f, i|
      failure_report += "### #{i + 1}. #{f[:app]} (#{f[:provider]})\n\n"
      failure_report += "- **Error:** #{f[:error]}\n\n"
    end

    failure_file = "tmp/test_results/matrix_failures_#{run_id}.md"
    File.write(failure_file, failure_report)
    puts "❌ Failure report: #{failure_file}"
  end

  # Console summary
  puts "\n" + "=" * 60
  puts "Provider Matrix Test Summary"
  puts "=" * 60
  puts "Total: #{total} | Passed: #{total_passed} ✅ | Failed: #{total_failed} #{total_failed > 0 ? '❌' : ''}"
  puts "Pass Rate: #{pass_rate}%"
  puts ""
  puts "Provider Breakdown:"
  providers.each do |provider, stats|
    status = stats[:failed] == 0 ? '✅' : '❌'
    puts "  #{provider.ljust(12)} #{stats[:passed]}/#{stats[:total]} #{status}"
  end
  puts "=" * 60
end
