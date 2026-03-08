# frozen_string_literal: false

# Static file serving, documentation, and root page routes

# Accept requests from the client
get "/" do
  @timestamp = Time.now.to_i
  session[:parameters] ||= {}
  session[:messages] ||= []
  session[:version] = Monadic::VERSION
  session[:docker] = Monadic::Utils::Environment.in_container?

  # Get UI language from environment variable (set by Electron app)
  @ui_language = ENV['UI_LANGUAGE'] || 'en'

  # Pass DEBUG_MODE to template for conditional local documentation link
  @debug_mode = CONFIG["DEBUG_MODE"] || false

  # Check if this is a WebSocket upgrade request
  if env["HTTP_UPGRADE"]&.downcase == "websocket" && env["HTTP_CONNECTION"]&.downcase&.include?("upgrade")
    websocket_handler(env)
  else
    erb :index
  end
end

# Serve local development documentation in debug mode (internal docs_dev)
# NOTE: This MUST come before the /docs/?* route to avoid matching /docs_dev/ as /docs/_dev/
get "/docs_dev/?*" do
  # Only serve docs_dev in debug mode
  unless CONFIG["DEBUG_MODE"]
    status 404
    return "Documentation not available in production mode"
  end

  # Get the requested path (remove leading /docs_dev/)
  requested_path = params[:splat].first || ""

  # Security: prevent path traversal attacks
  requested_path = requested_path.gsub(/\.\./, "")

  # Determine the docs_dev root directory (relative to lib/monadic.rb)
  # From docker/services/ruby/lib/monadic.rb to docs_dev/
  docs_dev_root = File.expand_path("../../../../../../../docs_dev", __FILE__)

  # Log the request for debugging
  Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Docs_dev request: requested_path='#{requested_path}', docs_dev_root='#{docs_dev_root}'" }

  # Build the full file path
  if requested_path.empty?
    file_path = File.join(docs_dev_root, "index.html")
  else
    file_path = File.join(docs_dev_root, requested_path)
  end

  Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Trying to serve: #{file_path}" }

  # Check if file exists and is within docs_dev directory
  if File.exist?(file_path) && !File.directory?(file_path)
    real_file_path = File.realpath(file_path)
    real_docs_dev_root = File.realpath(docs_dev_root)

    if real_file_path.start_with?(real_docs_dev_root)
      ext = File.extname(file_path)
      content_type DOCS_CONTENT_TYPE_MAP[ext] || "text/plain"

      Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Serving file: #{file_path} (#{DOCS_CONTENT_TYPE_MAP[ext]})" }
      send_file file_path
    else
      Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Security violation: #{real_file_path} not within #{real_docs_dev_root}" }
      status 403
      "Access forbidden"
    end
  else
    Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] File not found or is directory: #{file_path}" }
    status 404
    "File not found: #{requested_path}"
  end
end

# Serve local documentation in debug mode (public docs)
get "/docs/?*" do
  # Only serve docs in debug mode
  unless CONFIG["DEBUG_MODE"]
    status 404
    return "Documentation not available in production mode"
  end

  # Get the requested path (remove leading /docs/)
  requested_path = params[:splat].first || ""

  # Security: prevent path traversal attacks
  requested_path = requested_path.gsub(/\.\./, "")

  # Determine the docs root directory (relative to lib/monadic.rb)
  # From docker/services/ruby/lib/monadic.rb to docs/
  docs_root = File.expand_path("../../../../../../../docs", __FILE__)

  # Log the request for debugging
  Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Docs request: requested_path='#{requested_path}', docs_root='#{docs_root}'" }

  # Build the full file path
  if requested_path.empty?
    file_path = File.join(docs_root, "index.html")
  else
    file_path = File.join(docs_root, requested_path)
  end

  Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Trying to serve: #{file_path}" }

  # Check if file exists and is within docs directory
  if File.exist?(file_path) && !File.directory?(file_path)
    real_file_path = File.realpath(file_path)
    real_docs_root = File.realpath(docs_root)

    if real_file_path.start_with?(real_docs_root)
      ext = File.extname(file_path)
      content_type DOCS_CONTENT_TYPE_MAP[ext] || "text/plain"

      Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Serving file: #{file_path} (#{DOCS_CONTENT_TYPE_MAP[ext]})" }
      send_file file_path
    else
      Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] Security violation: #{real_file_path} not within #{real_docs_root}" }
      status 403
      "Access forbidden"
    end
  else
    Monadic::Utils::ExtraLogger.log { "[DEBUG_MODE] File not found or is directory: #{file_path}" }
    status 404
    "File not found: #{requested_path}"
  end
end

def fetch_file(file_name)
  # Prevent path traversal attacks by sanitizing the filename
  safe_name = File.basename(file_name)

  datadir = Monadic::Utils::Environment.data_path
  file_path = File.join(datadir, safe_name)

  begin
    # Resolve real paths to handle symlinks
    real_path = File.realpath(file_path) if File.exist?(file_path)
    real_datadir = File.realpath(datadir)

    # Ensure proper directory separator
    real_datadir_with_sep = real_datadir.end_with?(File::SEPARATOR) ?
                           real_datadir :
                           real_datadir + File::SEPARATOR

    if real_path && real_path.start_with?(real_datadir_with_sep) && File.exist?(file_path)
      send_file file_path
    else
      status 404
      "Sorry, the file you are looking for is unavailable."
    end
  rescue StandardError => e
    puts "File fetch error: #{e.message}" if ENV["DEBUG"]
    status 404
    "Sorry, the file you are looking for is unavailable."
  end
end

get "/monadic/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/data/:file_name" do
  fetch_file(params[:file_name])
end

get "/:filename" do |filename|
  redirect to("/data/#{filename}")
end
