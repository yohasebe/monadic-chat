# frozen_string_literal: true

require 'json'
require 'cgi'

class TestReportHTML
  def self.generate(results_dir, run_id, output_path)
    meta_file = File.join(results_dir, "#{run_id}_meta.json")

    unless File.exist?(meta_file)
      return nil
    end

    meta = JSON.parse(File.read(meta_file))

    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Test Report - #{run_id}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            margin: 40px;
            background: #f5f5f5;
          }
          .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          }
          h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
          h2 { color: #555; margin-top: 30px; }
          .summary {
            background: #e7f3ff;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
          }
          .passed { color: #28a745; font-weight: bold; }
          .failed { color: #dc3545; font-weight: bold; }
          .pending { color: #ffc107; font-weight: bold; }
          pre {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid #007bff;
          }
          .meta { color: #666; font-size: 0.9em; }
          table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
          }
          th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #ddd;
          }
          th {
            background: #007bff;
            color: white;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>Test Report</h1>
          <div class="meta">
            <p><strong>Run ID:</strong> #{run_id}</p>
            <p><strong>Generated:</strong> #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}</p>
          </div>

          <div class="summary">
            <h2>Summary</h2>
            <p><strong>Suite:</strong> #{meta['suite'] || 'Unknown'}</p>
            <p><strong>Status:</strong> <span class="#{meta['status']}">#{meta['status']}</span></p>
            <p><strong>Examples:</strong> #{meta['examples'] || 0}</p>
            <p><strong>Failures:</strong> #{meta['failures'] || 0}</p>
            <p><strong>Pending:</strong> #{meta['pending'] || 0}</p>
          </div>
    HTML

    # Add RSpec output if available
    rspec_file = File.join(results_dir, "#{run_id}_rspec.txt")
    if File.exist?(rspec_file)
      rspec_output = File.read(rspec_file)
      html << <<~HTML
        <h2>RSpec Output</h2>
        <pre>#{CGI.escapeHTML(rspec_output)}</pre>
      HTML
    end

    # Add Jest output if available
    jest_file = File.join(results_dir, "#{run_id}_jest.txt")
    if File.exist?(jest_file)
      jest_output = File.read(jest_file)
      html << <<~HTML
        <h2>Jest Output</h2>
        <pre>#{CGI.escapeHTML(jest_output)}</pre>
      HTML
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
