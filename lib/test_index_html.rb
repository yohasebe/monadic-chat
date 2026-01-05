# frozen_string_literal: true

require 'json'

class TestIndexHTML
  def self.generate(results_dir, run_id, suites, output_path)
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Test Results - #{run_id}</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px; }
          h1 { color: #333; }
          .suite { margin: 20px 0; padding: 15px; border-radius: 5px; }
          .suite.passed { background: #d4edda; border: 1px solid #c3e6cb; }
          .suite.failed { background: #f8d7da; border: 1px solid #f5c6cb; }
          .suite.pending { background: #fff3cd; border: 1px solid #ffeaa7; }
          .suite h2 { margin-top: 0; }
          a { color: #007bff; text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <h1>Test Results Summary</h1>
        <p><strong>Run ID:</strong> #{run_id}</p>
        <p><strong>Time:</strong> #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}</p>
    HTML

    suites.each do |suite|
      status_class = suite[:status] == 'passed' ? 'passed' : suite[:status] == 'pending' ? 'pending' : 'failed'
      suite_name = suite[:name].to_s.capitalize
      html << <<~SUITE
        <div class="suite #{status_class}">
          <h2>#{suite_name} Tests</h2>
          <p><strong>Status:</strong> #{suite[:status]}</p>
          <p><a href="report_#{suite[:run_id]}.html">View Report</a></p>
        </div>
      SUITE
    end

    html << <<~HTML
      </body>
      </html>
    HTML

    File.write(output_path, html)
    output_path
  end

  # Generate unified index HTML for test:all results
  # All test results are in the same directory with simple filenames
  def self.generate_unified(output_dir, run_id, suites, output_path)
    # Try to read summary.json for overall stats
    summary_file = File.join(output_dir, 'summary.json')
    summary = File.exist?(summary_file) ? JSON.parse(File.read(summary_file)) : {}

    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Test Results - #{run_id}</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px; background: #f5f5f5; }
          .container { max-width: 900px; margin: 0 auto; }
          h1 { color: #333; margin-bottom: 10px; }
          .meta { color: #666; margin-bottom: 30px; }
          .suites { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }
          .suite { padding: 20px; border-radius: 8px; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .suite.passed { border-left: 4px solid #28a745; }
          .suite.failed { border-left: 4px solid #dc3545; }
          .suite.skipped { border-left: 4px solid #6c757d; }
          .suite h2 { margin: 0 0 10px 0; font-size: 1.2em; }
          .suite .status { font-weight: bold; }
          .suite .status.passed { color: #28a745; }
          .suite .status.failed { color: #dc3545; }
          .suite a { color: #007bff; text-decoration: none; font-size: 0.9em; }
          .suite a:hover { text-decoration: underline; }
          .stats { margin: 20px 0; padding: 15px; background: white; border-radius: 8px; }
          .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 15px; text-align: center; }
          .stat-item { padding: 10px; }
          .stat-value { font-size: 2em; font-weight: bold; }
          .stat-label { color: #666; font-size: 0.9em; }
          .failures { margin-top: 30px; background: #fff5f5; padding: 20px; border-radius: 8px; border: 1px solid #ffcccc; }
          .failures h2 { color: #dc3545; margin-top: 0; }
          .failure-item { margin: 10px 0; padding: 10px; background: white; border-radius: 4px; }
          .failure-location { font-family: monospace; font-size: 0.85em; color: #666; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>🧪 Test Results</h1>
          <div class="meta">
            <strong>Run ID:</strong> #{run_id}<br>
            <strong>Time:</strong> #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}<br>
            <strong>Duration:</strong> #{summary['duration'] || 'N/A'}s
          </div>
    HTML

    # Collect stats from all JSON files
    total_tests = 0
    total_passed = 0
    total_failed = 0
    total_pending = 0
    all_failures = []

    suites.each do |suite|
      json_file = File.join(output_dir, suite[:file])
      next unless File.exist?(json_file) && suite[:file].end_with?('.json')

      begin
        data = JSON.parse(File.read(json_file))
        examples = data['examples'] || []

        examples.each do |ex|
          total_tests += 1
          case ex['status']
          when 'passed'
            total_passed += 1
          when 'failed'
            total_failed += 1
            all_failures << {
              suite: suite[:name],
              description: ex['full_description'] || ex['description'],
              location: "#{ex['file_path']}:#{ex['line_number']}",
              message: ex.dig('exception', 'message')
            }
          when 'pending'
            total_pending += 1
          end
        end
      rescue JSON::ParserError
        # Skip malformed JSON files
      end
    end

    # Stats section
    html << <<~HTML
          <div class="stats">
            <div class="stats-grid">
              <div class="stat-item">
                <div class="stat-value">#{total_tests}</div>
                <div class="stat-label">Total</div>
              </div>
              <div class="stat-item">
                <div class="stat-value" style="color: #28a745;">#{total_passed}</div>
                <div class="stat-label">Passed</div>
              </div>
              <div class="stat-item">
                <div class="stat-value" style="color: #dc3545;">#{total_failed}</div>
                <div class="stat-label">Failed</div>
              </div>
              <div class="stat-item">
                <div class="stat-value" style="color: #ffc107;">#{total_pending}</div>
                <div class="stat-label">Pending</div>
              </div>
            </div>
          </div>
          <div class="suites">
    HTML

    # Suite cards
    suites.each do |suite|
      status = suite[:status] ? 'passed' : 'failed'
      status_class = suite[:status] ? 'passed' : 'failed'
      status_text = suite[:status] ? '✅ Passed' : '❌ Failed'
      file_link = suite[:file]

      html << <<~SUITE
            <div class="suite #{status_class}">
              <h2>#{suite[:name].to_s.capitalize}</h2>
              <p class="status #{status_class}">#{status_text}</p>
              <a href="#{file_link}">View Results (#{file_link})</a>
            </div>
      SUITE
    end

    html << "      </div>\n"

    # Failures section
    if all_failures.any?
      html << <<~HTML
          <div class="failures">
            <h2>❌ Failed Tests (#{all_failures.size})</h2>
      HTML

      all_failures.first(50).each_with_index do |f, i|
        html << <<~FAILURE
            <div class="failure-item">
              <strong>#{i + 1}. [#{f[:suite]}] #{f[:description]}</strong>
              <div class="failure-location">#{f[:location]}</div>
              #{f[:message] ? "<div style='color: #666; margin-top: 5px;'>#{f[:message][0..200]}</div>" : ''}
            </div>
        FAILURE
      end

      html << "      </div>\n"
    end

    html << <<~HTML
        </div>
      </body>
      </html>
    HTML

    File.write(output_path, html)
    output_path
  end
end
