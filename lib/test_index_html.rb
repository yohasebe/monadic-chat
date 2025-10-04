# frozen_string_literal: true

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
end
