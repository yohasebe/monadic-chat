# frozen_string_literal: true

# Documentation server
desc "Generate workflow SVG diagrams for documentation"
task :generate_workflow_svgs, [:server] do |_t, args|
  server = args[:server] || "http://localhost:4567"

  # Check if server is reachable
  require "net/http"
  begin
    uri = URI("#{server}/api/apps/graph_list")
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      puts "Error: Server returned HTTP #{res.code}"
      puts "Make sure the Monadic Chat server is running: rake server:debug"
      exit 1
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    puts "Error: Cannot connect to #{server} (#{e.message})"
    puts "Start the server first: rake server:debug"
    exit 1
  end

  puts "Generating workflow SVGs from #{server} ..."
  sh "npm run generate:workflows -- --server #{server}"
  puts "Done. SVGs are in docs/assets/images/workflows/"
end

desc "Start docsify documentation server"
task :docs do
  puts "Starting docsify documentation server..."
  puts "Documentation will be available at: http://localhost:3000"
  puts "Press Ctrl+C to stop the server"
  sh "docsify serve ./docs"
end
