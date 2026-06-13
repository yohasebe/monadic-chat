# frozen_string_literal: true

# Server management tasks
namespace :server do
  desc "Start the Monadic server in daemonized mode"
  task :start do
    puts "Starting Monadic server..."

    # Check if vendor assets are available
    vendor_js_path = File.expand_path("docker/services/ruby/public/vendor/js/jquery.min.js")
    vendor_css_path = File.expand_path("docker/services/ruby/public/vendor/css/bootstrap.min.css")

    unless File.exist?(vendor_js_path) && File.exist?(vendor_css_path)
      puts "\n" + "="*80
      puts "📦 Vendor assets not found. Downloading required files..."
      puts "="*80 + "\n"

      # Download vendor assets
      Rake::Task['download_vendor_assets'].invoke

      puts "\n" + "="*80
      puts "✅ Vendor assets downloaded successfully"
      puts "="*80 + "\n"
    end

    sh "./bin/monadic_server.sh start"
  end
  
  desc "Start development server using CLI-managed Docker (no Electron)"
  task :debug do
    puts "Starting Monadic development server (Docker-managed via CLI)..."

    # No JS bundle step in dev. The dev server (host Falcon) serves the raw JS
    # source files directly in bundle order (see static_routes.rb @dev_js_files
    # + index.erb), so edits show on reload with no rebuild and nothing can go
    # stale. The minified single bundle is a production-only artifact, built by
    # `npm run build:js` / at packaging time and loaded only inside the container.

    # Force EXTRA_LOGGING to true in debug mode
    ENV['EXTRA_LOGGING'] = 'true'
    puts "Extra logging: enabled (forced in debug mode)"

    # Enable DEBUG_MODE for local documentation
    ENV['DEBUG_MODE'] = 'true'
    puts "Debug mode: enabled (local documentation available)"

    # Check for API keys in environment or config file
    require 'dotenv'
    config_path = File.expand_path("~/monadic/config/env")
    if File.exist?(config_path)
      Dotenv.load(config_path)
    end
    
    # List of common API keys to check
    api_keys = {
      'OPENAI_API_KEY' => 'OpenAI',
      'ANTHROPIC_API_KEY' => 'Anthropic (Claude)',
      'GEMINI_API_KEY' => 'Google Gemini',
      'MISTRAL_API_KEY' => 'Mistral AI',
      'COHERE_API_KEY' => 'Cohere',
      'DEEPSEEK_API_KEY' => 'DeepSeek',
      'XAI_API_KEY' => 'xAI (Grok)',
      'ELEVENLABS_API_KEY' => 'ElevenLabs (TTS)'
    }
    
    # Check which API keys are defined
    defined_keys = []
    missing_keys = []
    
    api_keys.each do |key, provider|
      if ENV[key] && !ENV[key].empty?
        defined_keys << provider
      else
        missing_keys << provider
      end
    end
    
    # Display warning if no API keys are defined
    if defined_keys.empty?
      puts "\n" + "="*80
      puts "⚠️  WARNING: No API keys found!"
      puts "="*80
      puts "\nMonadic Chat requires at least one API key to function properly."
      puts "\nPlease add API keys to: ~/monadic/config/env"
      puts "\nExample format:"
      puts "  OPENAI_API_KEY=your-api-key-here"
      puts "  ANTHROPIC_API_KEY=your-api-key-here"
      puts "\nMissing API keys for: #{missing_keys.join(', ')}"
      puts "="*80 + "\n"
    else
      puts "\nAPI keys found for: #{defined_keys.join(', ')}"
      if !missing_keys.empty?
        puts "Missing API keys for: #{missing_keys.join(', ')}"
      end
    end

    # Check if vendor assets are available
    vendor_js_path = File.expand_path("docker/services/ruby/public/vendor/js/jquery.min.js")
    vendor_css_path = File.expand_path("docker/services/ruby/public/vendor/css/bootstrap.min.css")

    unless File.exist?(vendor_js_path) && File.exist?(vendor_css_path)
      puts "\n" + "="*80
      puts "📦 Vendor assets not found. Downloading required files..."
      puts "="*80 + "\n"

      # Download vendor assets
      Rake::Task['download_vendor_assets'].invoke

      puts "\n" + "="*80
      puts "✅ Vendor assets downloaded successfully"
      puts "="*80 + "\n"
    end

    # Stop Docker Ruby container if running (it would conflict with local server)
    puts "\n" + "="*80
    puts "🐳 Checking for Docker Ruby container..."
    puts "="*80 + "\n"

    ruby_container_names = ["monadic-chat-ruby-container", "ruby-container"]
    ruby_container_names.each do |container_name|
      container_status = `docker container inspect #{container_name} --format '{{.State.Status}}' 2>/dev/null`.strip
      if container_status == "running"
        puts "Found running Docker Ruby container: #{container_name}"
        puts "Stopping it to avoid port conflict..."
        system("docker stop #{container_name} >/dev/null 2>&1")
        puts "✅ Docker Ruby container stopped"
        break
      end
    end

    # Clean up any existing processes using port 4567
    puts "\n" + "="*80
    puts "🧹 Checking for existing server processes on port 4567..."
    puts "="*80 + "\n"

    # Find all processes using port 4567 (more reliable than pgrep)
    port_pids = `lsof -ti :4567 2>/dev/null`.strip
    unless port_pids.empty?
      pid_list = port_pids.split("\n")
      puts "Found processes using port 4567 (PIDs: #{pid_list.join(', ')})"
      puts "Stopping them gracefully..."

      # Try graceful shutdown first (SIGTERM)
      pid_list.each do |pid|
        system("kill -TERM #{pid} 2>/dev/null")
      end
      sleep 2

      # Check if still running, then force kill
      still_running = `lsof -ti :4567 2>/dev/null`.strip
      unless still_running.empty?
        puts "Some processes still running, forcing shutdown..."
        still_running.split("\n").each do |pid|
          system("kill -9 #{pid} 2>/dev/null")
        end
        sleep 1
      end

      # Final verification
      final_check = `lsof -ti :4567 2>/dev/null`.strip
      unless final_check.empty?
        puts "\n" + "="*80
        puts "⚠️  WARNING: Failed to stop all processes on port 4567"
        puts "="*80
        puts "\nStill running PIDs: #{final_check.split("\n").join(', ')}"
        puts "Please manually stop these processes or use a different port."
        puts "="*80 + "\n"
        exit 1
      end

      puts "✅ All processes stopped successfully"
    else
      puts "No existing processes found on port 4567."
    end

    puts "="*80 + "\n"

    # Start the development server (Docker startup handled by monadic_dev)
    sh "./bin/monadic_server.sh debug"
  end
  
  desc "Stop the Monadic server"
  task :stop do
    puts "Stopping Monadic server..."
    sh "./bin/monadic_server.sh stop"
  end
  
  desc "Restart the Monadic server"
  task :restart do
    puts "Restarting Monadic server..."
    sh "./bin/monadic_server.sh restart"
  end
  
  desc "Show the status of the Monadic server and containers"
  task :status do
    sh "./bin/monadic_server.sh status"
  end
end

# Database tasks
namespace :db do
  desc "Export the document database"
  task :export do
    puts "Exporting document database..."
    sh "./bin/monadic_server.sh export"
  end
  
  desc "Import the document database"
  task :import do
    puts "Importing document database..."
    sh "./bin/monadic_server.sh import"
  end
end

# Convenience shortcuts
desc "Start the Monadic server in daemonized mode (alias for server:start)"
task :start => "server:start"

desc "Start the Monadic server in debug mode (alias for server:debug)"
task :debug => "server:debug"

desc "Stop the Monadic server (alias for server:stop)"
task :stop => "server:stop"

desc "Show server status (alias for server:status)"
task :status => "server:status"
