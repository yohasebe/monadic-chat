# frozen_string_literal: true

require 'rspec/core'
require 'rspec/core/formatters'
require 'json'
require 'time'
require_relative 'test_run_dir'

module Monadic
  # RSpec additional formatter for compact end-of-run summaries and artifacts
  class SummaryFormatter
    RSpec::Core::Formatters.register self, :start, :example_passed, :example_failed, :example_pending, :dump_summary

    def initialize(output)
      @output = output
      @examples = []
      Monadic::TestRunDir.write_env_meta
    end

    def start(notification)
      @started_at = Time.now
      @total = notification.count
    end

    def example_passed(notification)
      record_example(notification.example, 'passed')
    end

    def example_failed(notification)
      record_example(notification.example, 'failed', notification.example.exception)
    end

    def example_pending(notification)
      record_example(notification.example, 'pending')
    end

    def dump_summary(summary)
      duration = summary.duration
      @seed = RSpec.configuration.seed  # Get seed from configuration
      counts = {
        total: summary.example_count,
        passed: summary.examples.count { |e| e.execution_result.status == :passed },
        failed: summary.failure_count,
        pending: summary.pending_count
      }

      # Write machine-readable report
      write_json_report(counts, duration)

      # Write markdown summaries
      compact_path = write_compact_md(counts, duration)
      write_full_md(counts, duration)

      # Update latest pointers
      Monadic::TestRunDir.update_latest(compact_source: compact_path)

      # Console one-page summary
      print_console_summary(counts, duration)
    end

    private

    def record_example(example, status, exception = nil)
      @examples << {
        id: example.id,
        description: example.full_description,
        file_path: example.metadata[:file_path],
        line_number: example.metadata[:line_number],
        status: status,
        run_time: example.execution_result.run_time,
        pending_message: example.execution_result.pending_message,
        exception: exception ? summarize_exception(exception) : nil
      }
    end

    def summarize_exception(ex)
      {
        class: ex.class.name,
        message: ex.message.to_s.lines.first(2).join(" ").strip,
        backtrace: filter_backtrace(ex.backtrace)
      }
    end

    def filter_backtrace(bt)
      return [] unless bt
      root = Monadic::TestRunDir.project_root
      project_bt = bt.select { |l| l.include?(root) || l.include?('/spec/') }
      (project_bt.empty? ? bt : project_bt).first(20)
    end

    def write_json_report(counts, duration)
      payload = {
        counts: counts,
        duration_seconds: duration,
        seed: @seed,
        started_at: (@started_at.utc.iso8601 rescue @started_at.utc.to_s),
        finished_at: (Time.now.utc.iso8601 rescue Time.now.utc.to_s),
        examples: @examples
      }
      File.write(Monadic::TestRunDir.path('rspec_report.json'), JSON.pretty_generate(payload))
    rescue => e
      @output.puts("[summary] failed to write rspec_report.json: #{e.message}")
    end

    def suite_breakdown
      buckets = Hash.new(0)
      @examples.each do |ex|
        fp = ex[:file_path].to_s
        key = case fp
              when /spec\/unit/ then 'unit'
              when /spec\/integration/ then 'integration'
              when /spec\/system/ then 'system'
              when /spec\/e2e/ then 'e2e'
              else 'other'
              end
        buckets[key] += 1
      end
      buckets
    end

    def write_compact_md(counts, duration)
      ts = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      sb = []
      sb << "# Test Summary – #{ts}"
      sb << ""
      sb << "- Total: #{counts[:total]} • Passed: #{counts[:passed]} • Failed: #{counts[:failed]} • Pending: #{counts[:pending]} • Duration: #{format_duration(duration)}"
      breakdown = suite_breakdown.map { |k,v| v>0 ? "#{k}(#{v})" : nil }.compact.join(' ')
      sb << "- Suite: #{breakdown}"
      env_line = []
      %w[PROVIDERS RUN_API RUN_MEDIA INCLUDE_OLLAMA GEMINI_REASONING API_MAX_TOKENS GEMINI_MAX_TOKENS].each do |k|
        env_line << "#{k}=#{ENV[k]}" if ENV[k] && !ENV[k].empty?
      end
      sb << "- Env: #{env_line.join(' • ')}" unless env_line.empty?
      git = Monadic::TestRunDir.git_meta
      sb << "- Git: #{git[:branch]} @ #{git[:commit]}" if git[:branch] || git[:commit]
      sb << ""
      fails = @examples.select { |e| e[:status] == 'failed' }
      pendings = @examples.select { |e| e[:status] == 'pending' }
      if fails.any?
        sb << "## Failed (#{fails.size})"
        max = (ENV['SUMMARY_MAX_FAILS'] || '50').to_i
        fails.first(max).each_with_index do |e, i|
          reason = e[:exception] ? e[:exception][:message] : 'failed'
          sb << "#{i+1}. #{e[:description]} — #{rel_path(e[:file_path])}:#{e[:line_number]} — #{reason}"
        end
        if fails.size > max
          sb << "... and #{fails.size - max} more failures (see summary_full.md)"
        end
      end
      if pendings.any?
        sb << ""
        sb << "## Pending/Skipped (#{pendings.size})"
        maxp = (ENV['SUMMARY_MAX_PENDINGS'] || '50').to_i
        pendings.first(maxp).each do |e|
          sb << "- #{e[:description]} — #{rel_path(e[:file_path])}:#{e[:line_number]} — #{e[:pending_message]}"
        end
        if pendings.size > maxp
          sb << "... and #{pendings.size - maxp} more (see summary_full.md)"
        end
      end
      sb << ""
      sb << "Artifacts: #{File.dirname(Monadic::TestRunDir.path('summary_compact.md'))}"
      path = Monadic::TestRunDir.path('summary_compact.md')
      File.write(path, sb.join("\n"))
      path
    rescue => e
      @output.puts("[summary] failed to write summary_compact.md: #{e.message}")
      nil
    end

    def write_full_md(counts, duration)
      sb = []
      sb << "# Test Summary (Full)"
      sb << "- Total: #{counts[:total]} • Passed: #{counts[:passed]} • Failed: #{counts[:failed]} • Pending: #{counts[:pending]} • Duration: #{format_duration(duration)}"
      sb << ""
      fails = @examples.select { |e| e[:status] == 'failed' }
      if fails.any?
        sb << "## Failures"
        fails.each_with_index do |e, i|
          sb << "### #{i+1}. #{e[:description]}"
          sb << "Location: #{rel_path(e[:file_path])}:#{e[:line_number]}"
          if e[:exception]
            sb << "Error: #{e[:exception][:class]} — #{e[:exception][:message]}"
            if e[:exception][:backtrace]&.any?
              sb << "Backtrace:"
              e[:exception][:backtrace].each { |l| sb << "  - #{rel_path(l)}" }
            end
          end
          sb << ""
        end
      end
      pendings = @examples.select { |e| e[:status] == 'pending' }
      if pendings.any?
        sb << "## Pending/Skipped"
        pendings.each do |e|
          sb << "- #{e[:description]} — #{rel_path(e[:file_path])}:#{e[:line_number]} — #{e[:pending_message]}"
        end
      end
      File.write(Monadic::TestRunDir.path('summary_full.md'), sb.join("\n"))
    rescue => e
      @output.puts("[summary] failed to write summary_full.md: #{e.message}")
    end

    def rel_path(path)
      root = Monadic::TestRunDir.project_root
      path.to_s.start_with?(root) ? path[root.size+1..-1] : path.to_s
    end

    def format_duration(sec)
      return "#{sec.round(2)}s" if sec < 60
      m = (sec / 60).floor
      s = (sec - m*60).round
      "#{m}m#{s}s"
    end

    def print_console_summary(counts, duration)
      require 'rspec/core/formatters/console_codes'
      codes = RSpec::Core::Formatters::ConsoleCodes
      green = ->(s) { codes.wrap(s, :success) }
      red   = ->(s) { codes.wrap(s, :failure) }
      yellow= ->(s) { codes.wrap(s, :pending) }
      cyan  = ->(s) { codes.wrap(s, :detail) }

      line1 = []
      line1 << "Total: #{counts[:total]}"
      line1 << green.call("Passed: #{counts[:passed]}")
      line1 << (counts[:failed] > 0 ? red.call("Failed: #{counts[:failed]}") : "Failed: 0")
      line1 << (counts[:pending] > 0 ? yellow.call("Pending: #{counts[:pending]}") : "Pending: 0")
      line1 << "Duration: #{format_duration(duration)}"
      @output.puts("\n" + line1.join(' • '))

      fails = @examples.select { |e| e[:status] == 'failed' }
      if fails.any?
        @output.puts(red.call("Failed examples:"))
        max = (ENV['SUMMARY_MAX_FAILS'] || '50').to_i
        fails.first(max).each do |e|
          @output.puts("  - #{e[:description]} (#{rel_path(e[:file_path])}:#{e[:line_number]})")
        end
        if fails.size > max
          @output.puts("  ... and #{fails.size - max} more (see summary_full.md)")
        end
      end

      dir = File.dirname(Monadic::TestRunDir.path('summary_compact.md'))
      @output.puts(cyan.call("Artifacts: #{dir} (summary_compact.md, summary_full.md, rspec_report.json)"))
    rescue => e
      @output.puts("[summary] console summary failed: #{e.message}")
    end
  end
end
