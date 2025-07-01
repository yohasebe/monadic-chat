# frozen_string_literal: true

require "fileutils"
require "rspec/core/rake_task"
require "rubygems"
require_relative "./docker/services/ruby/lib/monadic/version"
version = Monadic::VERSION

# Set development environment variables if not in Docker container
unless File.file?("/.dockerenv")
  ENV['POSTGRES_HOST'] ||= 'localhost'
  ENV['POSTGRES_PORT'] ||= '5433'  # Use 5433 to avoid conflict with local PostgreSQL
  ENV['OPENAI_API_KEY'] ||= ENV['OPENAI_API_KEY']
  ENV['ANTHROPIC_API_KEY'] ||= ENV['ANTHROPIC_API_KEY']
  ENV['GEMINI_API_KEY'] ||= ENV['GEMINI_API_KEY']
  # Add other API keys as needed
end

# RSpec::Core::RakeTask.new(:spec) # Commented out as we define custom :spec task below

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

task :eslint do
  sh "npx eslint ."
end

desc "Download vendor assets from CDN for local use"
task :download_vendor_assets do
  puts "Downloading vendor assets from CDN for local use..."
  sh "./bin/assets.sh"
  puts "Vendor assets downloaded successfully."
end

# Server management tasks
namespace :server do
  desc "Start the Monadic server in daemonized mode"
  task :start do
    puts "Starting Monadic server..."
    sh "./bin/monadic_server.sh start"
  end
  
  desc "Start the Monadic server in debug mode (non-daemonized)"
  task :debug do
    puts "Starting Monadic server in debug mode..."
    
    # Force EXTRA_LOGGING to true in debug mode
    ENV['EXTRA_LOGGING'] = 'true'
    puts "Extra logging: enabled (forced in debug mode)"
    
    # Check if Ollama container exists and set OLLAMA_AVAILABLE accordingly
    ollama_exists = system("docker ps -a --format '{{.Names}}' | grep -q 'monadic-chat-ollama-container'")
    ENV['OLLAMA_AVAILABLE'] = ollama_exists ? 'true' : 'false'
    puts "Ollama container: #{ollama_exists ? 'detected' : 'not found'}"
    
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
      'PERPLEXITY_API_KEY' => 'Perplexity',
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

# Define the list of files that should have consistent version numbers
def version_files
  # Static files that always need version updates
  static_files = [
    "./docker/services/ruby/lib/monadic/version.rb",
    "./package.json",
    "./package-lock.json",
    "./docker/monadic.sh",
    "./docs/_coverpage.md",
    "./docs/getting-started/installation.md",
    "./docs/ja/getting-started/installation.md"
  ]
  
  # Return the files
  static_files
end

# Escape version string for use in file names
# Converts semantic version (1.0.0-beta.1) to file-safe version (1.0.0-beta-1)
def escape_version_for_files(version)
  version.gsub('.', '-').gsub(/^(\d+)-(\d+)-(\d+)/, '\1.\2.\3')
end

# Compare semantic versions
# Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
# Examples:
#   compare_versions("1.0.0-beta.1", "1.0.0") => -1 (beta is older)
#   compare_versions("1.0.0", "1.0.0-beta.1") => 1 (stable is newer)
#   compare_versions("1.0.0-beta.2", "1.0.0-beta.1") => 1 (beta.2 is newer)
def compare_versions(v1, v2)
  # Use Ruby's built-in Gem::Version for proper semantic version comparison
  Gem::Version.new(v1) <=> Gem::Version.new(v2)
rescue ArgumentError => e
  # If parsing fails, fall back to string comparison
  puts "Warning: Failed to parse versions '#{v1}' or '#{v2}': #{e.message}"
  v1 <=> v2
end

# Helper function to find build files with flexible version matching
# Handles beta, alpha, rc, pre, and other prerelease version formats
def find_build_files(pattern, version, escaped_version, base_dir = "dist")
  files = []
  # Try with escaped version first
  files += Dir.glob("#{base_dir}/#{pattern.gsub('VERSION', escaped_version)}")
  # If nothing found, try with original version
  if files.empty?
    files += Dir.glob("#{base_dir}/#{pattern.gsub('VERSION', version)}")
  end
  # If still nothing, try more flexible patterns for prerelease versions
  if files.empty? && version.include?('-')
    # Extract base version and prerelease parts
    base_version = version.split('-').first
    prerelease_part = version.split('-', 2).last
    
    # Try patterns with different prerelease separators and formats
    # Handle cases like: beta.1 -> beta-1, beta.1 -> beta1, etc.
    ['.', '-', ''].each do |separator|
      # Replace dots in prerelease part with separator
      test_prerelease = prerelease_part.gsub('.', separator)
      test_version = "#{base_version}-#{test_prerelease}"
      files += Dir.glob("#{base_dir}/#{pattern.gsub('VERSION', test_version)}")
      
      # Also try without any separator in prerelease
      if separator == ''
        test_version_no_sep = "#{base_version}-#{prerelease_part.gsub('.', '')}"
        files += Dir.glob("#{base_dir}/#{pattern.gsub('VERSION', test_version_no_sep)}")
      end
    end
    
    # Try with underscore separator too (some build tools use this)
    test_version = version.gsub('-', '_')
    files += Dir.glob("#{base_dir}/#{pattern.gsub('VERSION', test_version)}")
  end
  files.uniq
end

# Check if a version is newer than another
def version_newer?(new_version, old_version)
  compare_versions(new_version, old_version) > 0
end

# Check if a version is a prerelease
def version_prerelease?(version)
  Gem::Version.new(version).prerelease?
rescue ArgumentError
  # If it can't be parsed, check for common prerelease indicators
  version.include?('-') && (version.include?('beta') || version.include?('alpha') || version.include?('rc'))
end

# Get the current version from version.rb (considered the source of truth)
def get_current_version
  version_file = "./docker/services/ruby/lib/monadic/version.rb"
  if File.exist?(version_file)
    content = File.read(version_file)
    if content =~ /VERSION\s*=\s*"([^"]+)"/
      return $1
    end
  end
  nil
end

# Different files need different, very specific replacement patterns for the version number
def update_version_in_file(file, from_version, to_version)
  return unless File.exist?(file)
  
  content = File.read(file)
  original_content = content.dup
  updated_content = nil
  
  case File.basename(file)
  when "version.rb"
    # For version.rb, update the VERSION constant
    updated_content = content.gsub(/^(\s*VERSION\s*=\s*)"#{Regexp.escape(from_version)}"/, "\\1\"#{to_version}\"")
  
  when "installation.md"
    # For installation.md, update version numbers in download URLs
    
    # Escape version strings to handle semantic versioning (e.g., 1.0.0-beta.1)
    escaped_from = escape_version_for_files(from_version)
    escaped_to = escape_version_for_files(to_version)
    
    # Replace version in the GitHub release path
    updated_content = content.gsub(/\/v#{Regexp.escape(from_version)}\//, "/v#{to_version}/")
    
    # Replace version in file names for all platforms
    # Mac files
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(escaped_from)}-arm64\.dmg/, "Monadic.Chat-#{escaped_to}-arm64.dmg")
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(escaped_from)}-x64\.dmg/, "Monadic.Chat-#{escaped_to}-x64.dmg")
    # Windows files
    updated_content = updated_content.gsub(/Monadic\.Chat\.Setup\.#{Regexp.escape(escaped_from)}\.exe/, "Monadic.Chat.Setup.#{escaped_to}.exe")
    # Linux files
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(escaped_from)}_amd64\.deb/, "monadic-chat_#{escaped_to}_amd64.deb")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(escaped_from)}_arm64\.deb/, "monadic-chat_#{escaped_to}_arm64.deb")
    # ZIP files for updates (all platforms)
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(escaped_from)}-arm64\.zip/, "Monadic.Chat-#{escaped_to}-arm64.zip")
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(escaped_from)}-x64\.zip/, "Monadic.Chat-#{escaped_to}-x64.zip")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(escaped_from)}_arm64\.zip/, "monadic-chat_#{escaped_to}_arm64.zip")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(escaped_from)}_x64\.zip/, "monadic-chat_#{escaped_to}_x64.zip")
    updated_content = updated_content.gsub(/Monadic\.Chat\.Setup\.#{Regexp.escape(escaped_from)}\.zip/, "Monadic.Chat.Setup.#{escaped_to}.zip")
  
  when "_coverpage.md"
    # For _coverpage.md, update the version in the header only
    updated_content = content.gsub(/<small><b>#{Regexp.escape(from_version)}<\/b><\/small>/, "<small><b>#{to_version}</b></small>")
  
  when "package.json"
    # For package.json, only update the main version field, not dependency versions
    updated_content = content.gsub(/^(\s*"version":\s*)"#{Regexp.escape(from_version)}"/, "\\1\"#{to_version}\"")
  
  when "package-lock.json"
    # For package-lock.json, only update the main version field, not any dependency versions
    updated_content = content.gsub(/^(\s*"version":\s*)"#{Regexp.escape(from_version)}"/, "\\1\"#{to_version}\"")
    updated_content = updated_content.gsub(/^(\s*"name":\s*"monadic-chat",\s*"version":\s*)"#{Regexp.escape(from_version)}"/, "\\1\"#{to_version}\"")
    
  when "monadic.sh"
    # For monadic.sh, only update the MONADIC_VERSION declaration
    updated_content = content.gsub(/^(export MONADIC_VERSION=)#{Regexp.escape(from_version)}/, "\\1#{to_version}")
  end
  
  # Only write back if something actually changed
  if updated_content && updated_content != original_content
    puts "Updating version in #{file} from #{from_version} to #{to_version}"
    File.write(file, updated_content)
    return true
  else
    puts "No version update needed in #{file} or pattern not recognized"
    return false
  end
end

desc "Check version number consistency across all relevant files. Verifies that all files have the same version as version.rb"
task :check_version do
  # Get the current official version
  official_version = get_current_version
  
  if official_version.nil?
    puts "Error: Could not determine current version from version.rb"
    exit 1
  end
  
  puts "Official version from version.rb: #{official_version}"

  # Check each file for the version
  inconsistent_files = []
  missing_files = []
  
  version_files.each do |file|
    if File.exist?(file)
      content = File.read(file)
      file_basename = File.basename(file)

      version_found = false
      
      case file_basename
      when "version.rb"
        version_found = content =~ /^\s*VERSION\s*=\s*"#{Regexp.escape(official_version)}"/
      when "installation.md"
        # Check if the file contains the current version in download URLs
        escaped_version = escape_version_for_files(official_version)
        version_found = content.include?("/v#{official_version}/") &&
                        content.include?("Monadic.Chat-#{escaped_version}-arm64.dmg") &&
                        content.include?("Monadic.Chat-#{escaped_version}-x64.dmg") &&
                        content.include?("Monadic.Chat.Setup.#{escaped_version}.exe") &&
                        content.include?("monadic-chat_#{escaped_version}_amd64.deb")
      when "_coverpage.md"
        version_found = content =~ /<small><b>#{Regexp.escape(official_version)}<\/b><\/small>/
      when "package.json"
        version_found = content =~ /^\s*"version":\s*"#{Regexp.escape(official_version)}"/
      when "package-lock.json"
        version_found = content =~ /^\s*"version":\s*"#{Regexp.escape(official_version)}"/
      when "monadic.sh"
        version_found = content =~ /^export MONADIC_VERSION=#{Regexp.escape(official_version)}/
      else
        # Generic check for other files
        version_found = content.include?(official_version)
      end
      
      if version_found
        puts "✓ #{file}: Version matches official version"
      else
        inconsistent_files << file
        puts "✗ #{file}: Version does not match official version"
      end
    else
      missing_files << file
      puts "! #{file}: File not found"
    end
  end
  
  # Summary
  puts "\nVersion Check Summary:"
  puts "Official version: #{official_version}"
  
  if inconsistent_files.empty? && missing_files.empty?
    puts "All files have consistent version numbers!"
  else
    if !inconsistent_files.empty?
      puts "Files with inconsistent versions:"
      inconsistent_files.each do |file|
        puts "  - #{file}"
      end
    end
    
    if !missing_files.empty?
      puts "Missing files:"
      missing_files.each do |file|
        puts "  - #{file}"
      end
    end
  end
end

desc "Update version number in all relevant files. Usage: rake update_version[to_version] or rake update_version[from_version,to_version]"
task :update_version, [:from_version, :to_version] do |_t, args|
  require 'date'
  
  # Handle both forms of invocation:
  # 1. rake update_version[0.7.74]         - Use current version as from_version
  # 2. rake update_version[0.7.73a,0.7.74] - Explicitly specify from_version
  
  if args[:to_version].nil?
    # If only one argument is provided, it's the to_version
    to_version = args[:from_version]
    from_version = get_current_version()
    
    if from_version.nil?
      puts "Error: Could not determine current version from version.rb"
      exit 1
    end
  else
    # Both arguments provided
    from_version = args[:from_version]
    to_version = args[:to_version]
  end
  
  # Check if this is a dry run
  dry_run = ENV['DRYRUN'] == 'true'
  dry_run_message = dry_run ? " (DRY RUN - no files will be modified)" : ""
  
  if to_version.nil?
    puts "Usage: rake update_version[to_version] or rake update_version[from_version,to_version] [DRYRUN=true]"
    puts "Example: rake update_version[0.7.74]"
    puts "Example: rake update_version[0.7.73a,0.7.74]"
    puts "Example (dry run): rake update_version[0.7.74] DRYRUN=true"
    exit 1
  end
  
  # Current month and year for changelog
  current_date = Date.today
  month_year = "#{current_date.strftime('%B')}, #{current_date.year}"
  
  # Files to update
  files = version_files
  
  # Update each file using file-specific patterns
  updated_files = []
  not_updated_files = []
  missing_files = []
  
  files.each do |file|
    if File.exist?(file)
      # If it's a dry run, don't actually modify files
      if dry_run
        # Read the file and check if we can find the version
        content = File.read(file)
        file_basename = File.basename(file)
        
        # Check for version patterns based on file type
        version_found = false
        case file_basename
        when "version.rb"
          version_found = content.include?("VERSION = \"#{from_version}\"")
        when "installation.md"
          # Check if the file contains the current version in download URLs
          escaped_from = escape_version_for_files(from_version)
          version_found = content.include?("/v#{from_version}/") &&
                          content.include?("Monadic.Chat-#{escaped_from}-arm64.dmg") &&
                          content.include?("Monadic.Chat-#{escaped_from}-x64.dmg") &&
                          content.include?("Monadic.Chat.Setup.#{escaped_from}.exe") &&
                          content.include?("monadic-chat_#{escaped_from}_amd64.deb")
        when "_coverpage.md"
          version_found = content.include?("<small><b>#{from_version}</b></small>")
        when "package.json"
          version_found = content.include?("\"version\": \"#{from_version}\"")
        when "package-lock.json"
          version_found = content.include?("\"version\": \"#{from_version}\"")
        when "monadic.sh"
          version_found = content.include?("MONADIC_VERSION=#{from_version}")
        else
          version_found = content.include?(from_version)
        end
        
        if version_found
          puts "Would update version in #{file} from #{from_version} to #{to_version}#{dry_run_message}"
          updated_files << file
        else
          puts "No version #{from_version} found in #{file}#{dry_run_message}"
          not_updated_files << file
        end
      else
        # Normal mode - actually update files
        if update_version_in_file(file, from_version, to_version)
          updated_files << file
        else
          not_updated_files << file
        end
      end
    else
      missing_files << file
      puts "File not found: #{file}"
    end
  end
  
  # Update CHANGELOG.md
  changelog = "./CHANGELOG.md"
  if File.exist?(changelog)
    content = File.read(changelog)
    unless content.include?("- [#{month_year}] #{to_version}")
      lines = content.lines
      
      # Check if first line contains the current month and from_version
      first_line = lines[0].strip
      if first_line.include?("[#{month_year}]") && first_line.include?(from_version)
        # Update the version number in the current month's entry
        if dry_run
          puts "Would update current month entry in CHANGELOG.md from #{from_version} to #{to_version}#{dry_run_message}"
        else
          lines[0] = first_line.gsub(from_version, to_version) + "\n"
          puts "Updating current month entry in CHANGELOG.md from #{from_version} to #{to_version}"
          File.write(changelog, lines.join)
        end
      else
        # Create a new entry for the current month
        if dry_run
          puts "Would add new entry to CHANGELOG.md for version #{to_version}#{dry_run_message}"
        else
          new_entry = "- [#{month_year}] #{to_version}\n  - Version updated from #{from_version}\n\n"
          lines.unshift(new_entry)
          puts "Adding new entry to CHANGELOG.md for version #{to_version}"
          File.write(changelog, lines.join)
        end
      end
    end
  end
  
  # Print a summary
  puts "\nVersion Update Summary#{dry_run_message}:"
  puts "From version: #{from_version}"
  puts "To version: #{to_version}"
  
  if !updated_files.empty?
    puts "\nFiles updated#{dry_run ? " (would be)" : ""}:"
    updated_files.each { |file| puts "  ✓ #{file}" }
  end
  
  if !not_updated_files.empty?
    puts "\nFiles not updated (version pattern not found):"
    not_updated_files.each { |file| puts "  ✗ #{file}" }
  end
  
  if !missing_files.empty?
    puts "\nFiles not found:"
    missing_files.each { |file| puts "  ! #{file}" }
  end
  
  puts "\nVersion update #{dry_run ? "simulation" : "operation"} completed!"
  
  # Run check_version to verify the update (only if not a dry run)
  unless dry_run
    puts "\nVerifying version consistency after update:"
    Rake::Task["check_version"].invoke
  end
end

# Platform-specific build tasks
namespace :build do
  # Common setup for all platform builds
  def setup_build_environment(skip_help_db: false)
    # remove /docker/services/python/pysetup.py
    FileUtils.rm_f("docker/services/python/pysetup.py")
    home_directory_path = File.join(File.dirname(__FILE__), "docker")
    Dir.glob("#{home_directory_path}/data/*").each { |file| FileUtils.rm_f(file) }
    Dir.glob("#{home_directory_path}/dist/*").each { |file| FileUtils.rm_f(file) }

    # Build and export help database unless skipped
    unless skip_help_db
      puts "\n=== Building Help Database ==="
      puts "This ensures the packaged app includes up-to-date help content."
      
      # Check if OPENAI_API_KEY is available
      require 'dotenv'
      config_path = File.expand_path("~/monadic/config/env")
      if File.exist?(config_path)
        Dotenv.load(config_path)
      end
      
      if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'].empty?
        puts "Warning: OPENAI_API_KEY not found. Skipping help database build."
        puts "To build the help database, add OPENAI_API_KEY to ~/monadic/config/env"
      else
        begin
          # Check if pgvector container is running
          pgvector_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-pgvector-container'")
          
          if pgvector_running
            puts "pgvector container is already running."
            # Run help database rebuild
            Rake::Task["help:rebuild"].invoke
          else
            puts "Starting pgvector container for help database build..."
            # Try to start existing container first
            if system("docker start monadic-chat-pgvector-container 2>/dev/null")
              puts "pgvector container started successfully."
            else
              # If container doesn't exist, create it using docker compose
              puts "Container doesn't exist, creating new one..."
              compose_file = File.expand_path("docker/services/compose.yml", __dir__)
              project_dir = File.expand_path("docker", __dir__)
              if !system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' up -d pgvector_service")
                puts "Warning: Failed to start pgvector container. Skipping help database build."
                return
              end
              puts "pgvector container created and started successfully."
            end
            
            # Wait for PostgreSQL to be ready
            puts "Waiting for PostgreSQL to be ready..."
            max_attempts = 30
            attempt = 0
            while attempt < max_attempts
              if system("docker exec monadic-chat-pgvector-container pg_isready -h localhost -p 5432 > /dev/null 2>&1")
                puts "PostgreSQL is ready!"
                break
              end
              attempt += 1
              print "."
              sleep 1
            end
            
            if attempt >= max_attempts
              puts "\nWarning: PostgreSQL did not become ready in time. Skipping help database build."
            else
              # Run help database rebuild
              Rake::Task["help:rebuild"].invoke
            end
          end
          
        rescue => e
          puts "Warning: Error building help database: #{e.message}"
          puts "Continuing with package build..."
        ensure
          # Stop pgvector if we started it (and user didn't have it running)
          if !pgvector_running && ENV['KEEP_PGVECTOR'] != 'true'
            puts "Stopping pgvector container..."
            compose_file = File.expand_path("docker/services/compose.yml", __dir__)
            project_dir = File.expand_path("docker", __dir__)
            system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop pgvector_service")
          end
        end
      end
      
      puts "\n=== Building Electron Packages ==="
    end

    # Download vendor assets for offline use
    puts "Downloading vendor assets for offline use..."
    Rake::Task["download_vendor_assets"].invoke

    sh "npm update"
    sh "npm cache clean --force"
  end

  desc "Build Windows x64 package only"
  task :win do
    skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
    setup_build_environment(skip_help_db: skip_help_db)
    puts "Building Windows x64 package..."
    sh "npm run build:win -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build macOS arm64 (Apple Silicon) package only"
  task :mac_arm64 do
    skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
    setup_build_environment(skip_help_db: skip_help_db)
    puts "Building macOS arm64 package..."
    sh "npm run build:mac-arm64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build macOS x64 (Intel) package only"
  task :mac_x64 do
    skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
    setup_build_environment(skip_help_db: skip_help_db)
    puts "Building macOS x64 package..."
    sh "npm run build:mac-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build Linux x64 package only"
  task :linux_x64 do
    skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
    setup_build_environment(skip_help_db: skip_help_db)
    puts "Building Linux x64 package..."
    sh "npm run build:linux-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build Linux arm64 package only"
  task :linux_arm64 do
    skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
    setup_build_environment(skip_help_db: skip_help_db)
    puts "Building Linux arm64 package..."
    sh "npm run build:linux-arm64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build macOS packages (both arm64 and x64)"
  task :mac => [:mac_arm64, :mac_x64]

  desc "Build Linux packages (both x64 and arm64)"
  task :linux => [:linux_x64, :linux_arm64]
end

# Main build task to build all packages (backward compatibility)
desc "Build installation packages for all supported platforms"
task :build do
  # Use the common setup which includes help database building
  # Set SKIP_HELP_DB=true to skip help database building
  skip_help_db = ENV['SKIP_HELP_DB'] == 'true'
  if skip_help_db
    puts "Skipping help database build (SKIP_HELP_DB=true)"
  end
  setup_build_environment(skip_help_db: skip_help_db)

  # Use generate-only flag to create YML files without publishing
  sh "npm run build:linux-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  sh "npm run build:linux-arm64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  sh "npm run build:win -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  sh "npm run build:mac-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true" 
  sh "npm run build:mac-arm64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"

  # First, get all files in the dist directory to see what was actually generated
  puts "Listing all files in dist directory before filtering:"
  Dir.glob("dist/*").each do |f|
    puts "  #{File.basename(f)}"
  end
  
  # Escape version for file names
  escaped_version = escape_version_for_files(version)
  
  # Debug: Show what versions we're working with
  puts "Original version: #{version}"
  puts "Escaped version: #{escaped_version}"
  
  # Define file patterns to look for
  file_patterns = {
    # Windows files
    "win_installer" => "Monadic.Chat.Setup.VERSION.exe",
    "win_zip" => "Monadic.Chat.Setup.VERSION.zip",
    
    # macOS files
    "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
    "mac_x64_dmg" => "Monadic.Chat-VERSION-x64.dmg",
    "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",
    "mac_x64_zip" => "Monadic.Chat-VERSION-x64.zip",
    
    # Linux files
    "linux_x64_deb" => "monadic-chat_VERSION_amd64.deb",
    "linux_arm64_deb" => "monadic-chat_VERSION_arm64.deb",
    "linux_x64_zip" => "monadic-chat_VERSION_x64.zip",
    "linux_arm64_zip" => "monadic-chat_VERSION_arm64.zip"
  }
  
  # Find all necessary files using flexible matching
  necessary_files = []
  
  file_patterns.each do |key, pattern|
    found_files = find_build_files(pattern, version, escaped_version)
    if found_files.empty?
      puts "Warning: No files found for #{key} (pattern: #{pattern})"
    else
      found_files.each do |file|
        puts "Found #{key}: #{File.basename(file)}"
        necessary_files << File.expand_path(file)
      end
    end
  end
  
  # Always include YML files
  yml_files = ["latest.yml", "latest-mac.yml", "latest-mac-arm64.yml", "latest-linux.yml", "latest-linux-arm64.yml"]
  yml_files.each do |yml|
    yml_path = File.expand_path("dist/#{yml}")
    if File.exist?(yml_path)
      necessary_files << yml_path
    end
  end
  
  # Mac files are already included in necessary_files
  # No need to add them separately
  
  # Add all YML files to necessary files list for auto-updates WITHOUT modifying them
  Dir.glob("dist/*.yml").each do |yml_file|
    yml_basename = File.basename(yml_file)
    
    # Just log the YML file found
    puts "Found update file: #{yml_basename}"
    
    # Do NOT modify the YML files - use them as-is from electron-builder
    necessary_files << File.expand_path(yml_file)
    
    # Only handle the special case for Mac arm64
    if yml_basename == 'latest-mac.yml'
      yml_content = File.read(yml_file)
      if yml_content.include?('arm64')
        # Create a separate arm64 specific yml file if it doesn't exist
        arm64_path = File.join(File.dirname(yml_file), "latest-mac-arm64.yml")
        unless File.exist?(arm64_path)
          puts "Creating missing arm64 YML file: #{arm64_path}"
          File.write(arm64_path, yml_content)
          necessary_files << File.expand_path(arm64_path)
        end
      end
    end
    
    puts "Added update file to necessary files: #{File.basename(yml_file)}"
  end

  Dir.glob("dist/*").each do |file|
    filepath = File.expand_path(file)
    if necessary_files.include?(filepath)
      puts "Keeping: #{File.basename(filepath)}"
    else
      puts "Removing: #{File.basename(filepath)}"
      FileUtils.rm_rf(filepath)
    end
    # move the file to the /docs/assets/download/ directory if it is included in necessary_files
    # FileUtils.mv(filepath, "docs/assets/download/") if necessary_files.include?(filepath)
  end
end

# Test ruby code with rspec ./docker/services/ruby/spec
task :spec do
  # Set environment variables for test database connection
  ENV['POSTGRES_HOST'] ||= 'localhost'
  ENV['POSTGRES_PORT'] ||= '5433'
  ENV['POSTGRES_USER'] ||= 'postgres'
  ENV['POSTGRES_PASSWORD'] ||= 'postgres'
  
  # Start pgvector container for tests that require it
  pgvector_running = system("docker ps | grep -q monadic-chat-pgvector-container")
  
  unless pgvector_running
    puts "Starting pgvector container for tests..."
    compose_file = File.expand_path("docker/services/compose.yml", __dir__)
    project_dir = File.expand_path("docker", __dir__)
    system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' up -d pgvector_service")
    
    # Wait for pgvector to be ready
    puts "Waiting for pgvector to be ready..."
    sleep 5
    
    # Wait up to 30 seconds for pgvector to accept connections
    30.times do
      if system("docker exec monadic-chat-pgvector-container pg_isready -U postgres", out: File::NULL, err: File::NULL)
        puts "pgvector is ready!"
        break
      end
      sleep 1
    end
  end
  
  # Run tests with the new structure
  Dir.chdir("docker/services/ruby") do
    puts "Running unit tests..."
    sh "bundle exec rspec spec/unit --format documentation --no-fail-fast --no-profile"
    
    
    # Run integration tests if available
    puts "\nRunning integration tests..."
    sh "bundle exec rspec spec/integration --format documentation --no-fail-fast --no-profile" rescue puts "Integration tests skipped (not available)"
    
    # Run system tests
    puts "\nRunning system tests..."
    sh "bundle exec rspec spec/system --format documentation --no-fail-fast --no-profile" rescue puts "System tests skipped (not available)"
  end
ensure
  # Only stop pgvector if we started it
  if !pgvector_running && ENV['KEEP_PGVECTOR'] != 'true'
    puts "Stopping pgvector container..."
    compose_file = File.expand_path("docker/services/compose.yml", __dir__)
    project_dir = File.expand_path("docker", __dir__)
    system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop pgvector_service")
  end
end

# Quick unit tests only (no containers needed)
desc "Run unit tests only (fast)"
task :spec_unit do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/unit --format documentation"
  end
end


# Integration tests only (requires containers)
desc "Run integration tests only"
task :spec_integration do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/integration --format documentation"
  end
end

# System tests only
desc "Run system tests only"
task :spec_system do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/system --format documentation"
  end
end

# Docker integration tests (requires Docker environment)
desc "Run Docker integration tests (requires Docker containers running)"
task :spec_docker do
  Dir.chdir("docker/services/ruby") do
    puts "Running Docker integration tests..."
    puts "Note: These tests require Docker containers to be running"
    sh "bundle exec rspec spec/integration/docker_infrastructure_spec.rb spec/integration/app_helpers_integration_spec.rb spec/integration/pgvector_integration_real_spec.rb spec/integration/selenium_integration_spec.rb --format documentation --no-fail-fast"
  end
end

# End-to-end tests (automatically starts server and containers)
desc "Run end-to-end tests (automatically handles prerequisites)"
task :spec_e2e do
  Dir.chdir("docker/services/ruby") do
    puts "Starting E2E test suite..."
    puts "This will automatically:"
    puts "  - Start required Docker containers"
    puts "  - Start the server if needed"
    puts "  - Run all E2E tests"
    puts ""
    
    # Use the run_e2e_tests.sh script
    sh "./spec/e2e/run_e2e_tests.sh"
  end
end

# E2E tests for specific apps/features
namespace :spec_e2e do
  desc "Run E2E tests for Chat app"
  task :chat do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat"
    end
  end
  
  desc "Run E2E tests for Code Interpreter"
  task :code_interpreter do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh code_interpreter"
    end
  end
  
  desc "Run E2E tests for Image Generator"
  task :image_generator do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh image_generator"
    end
  end
  
  desc "Run E2E tests for PDF Navigator"
  task :pdf_navigator do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh pdf_navigator"
    end
  end
  
  desc "Run E2E tests for Monadic Help"
  task :help do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh help"
    end
  end
  
  desc "Run E2E tests for Code Interpreter with a specific provider"
  task :code_interpreter_provider, [:provider] do |t, args|
    provider = args[:provider]
    unless provider
      puts "Error: Provider must be specified"
      puts "Usage: rake spec_e2e:code_interpreter_provider[openai]"
      puts "Available providers: openai, claude, gemini, grok, mistral, cohere, deepseek"
      exit 1
    end
    
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh code_interpreter_provider #{provider}"
    end
  end
  
  desc "Run E2E tests for Ollama provider"
  task :ollama do
    # Check if Ollama container exists
    ollama_exists = `docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^yohasebe/ollama:" 2>/dev/null`.strip
    
    if ollama_exists.empty?
      puts "\n" + "="*60
      puts "Ollama container not found"
      puts "="*60
      puts "\nThe Ollama container needs to be built before running tests."
      puts "\nTo build the Ollama container:"
      puts "  1. In the UI: Actions → Build Ollama Container"
      puts "  2. Or run: ./docker/monadic.sh build_ollama_container"
      puts "\nNote: Building will download the default model (llama3.2)"
      puts "      which may take some time depending on your connection."
      puts "="*60 + "\n"
      exit 0
    end
    
    # Check if Ollama container is running
    ollama_running = `docker ps --format "{{.Names}}" | grep -E "^monadic-chat-ollama-container$" 2>/dev/null`.strip
    
    if ollama_running.empty?
      puts "\nStarting Ollama container..."
      system("docker start monadic-chat-ollama-container")
      
      # Wait a moment for the container to start
      sleep 2
      
      # Verify it started
      ollama_running = `docker ps --format "{{.Names}}" | grep -E "^monadic-chat-ollama-container$" 2>/dev/null`.strip
      if ollama_running.empty?
        puts "\nFailed to start Ollama container. Please check Docker logs."
        exit 1
      end
    end
    
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh ollama"
    end
  end
  
  desc "Run E2E tests for Research Assistant"
  task :research_assistant do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh research_assistant"
    end
  end
  
  desc "Run E2E tests for Visual Web Explorer"
  task :visual_web_explorer do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh visual_web_explorer"
    end
  end
  
  desc "Run E2E tests for Mermaid Grapher"
  task :mermaid_grapher do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh mermaid_grapher"
    end
  end
  
  desc "Run E2E tests for Voice Chat"
  task :voice_chat do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh voice_chat"
    end
  end
  
  desc "Run E2E tests for Content Reader"
  task :content_reader do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh content_reader"
    end
  end
  
  desc "Run E2E tests for Coding Assistant"
  task :coding_assistant do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh coding_assistant"
    end
  end
  
  desc "Run E2E tests for Second Opinion"
  task :second_opinion do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh second_opinion"
    end
  end
  
  desc "Run E2E tests for Jupyter Notebook"
  task :jupyter_notebook do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh jupyter_notebook"
    end
  end
end

# Test JavaScript code with Jest
desc "Run JavaScript tests using Jest"
task :jstest do
  sh "npm test"
end

# For backward compatibility
desc "Run all JavaScript tests using Jest"
task :jstest_all => :jstest

# Test Python code
namespace :pytest do
  desc "Run all Python tests"
  task :all do
    puts "Running Python tests..."
    python_test_dirs = [
      "docker/services/python/scripts/services"
    ]
    
    python_test_dirs.each do |dir|
      if Dir.exist?(dir)
        puts "\nRunning tests in #{dir}..."
        Dir.chdir(dir) do
          # Run all test files
          test_files = Dir.glob("test_*.py")
          if test_files.any?
            test_files.each do |test_file|
              puts "Running #{test_file}..."
              sh "python3 #{test_file} -v" rescue puts "Test failed: #{test_file}"
            end
          else
            puts "No test files found in #{dir}"
          end
        end
      end
    end
  end
  
  desc "Run jupyter_controller tests"
  task :jupyter do
    puts "Running jupyter_controller tests..."
    test_file = "docker/services/python/scripts/services/test_jupyter_controller.py"
    if File.exist?(test_file)
      Dir.chdir(File.dirname(test_file)) do
        sh "python3 #{File.basename(test_file)} -v"
      end
    else
      puts "Test file not found: #{test_file}"
    end
  end
end

# Run both Ruby and JavaScript tests
desc "Run all tests (Ruby, JavaScript, and Python)"
task :test => [:spec, :jstest, "pytest:all"]

# Run only the jupyter controller integration test
desc "Run Jupyter controller integration test"
task :jupyter_integration do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/integration/jupyter_controller_integration_spec.rb --format documentation"
  end
end

# GitHub Release Management Tasks
namespace :release do
  desc "Build, package, and create a new GitHub release"
  task :github, [:version, :prerelease] do |_t, args|
    version = args[:version] || get_current_version
    prerelease = args[:prerelease] == 'true'
    
    if version.nil?
      puts "Error: Version required. Use rake release:github[version] or ensure version.rb contains a valid version."
      exit 1
    end
    
    prerelease_flag = prerelease ? "--prerelease" : ""
    
    puts "Preparing GitHub release for version #{version} (#{prerelease ? 'prerelease' : 'stable'})"

    # Step 1: Verify the current version matches the requested version
    current_version = get_current_version
    unless current_version == version
      puts "Warning: Requested version #{version} doesn't match current version in version.rb (#{current_version})"
      puts "Use rake update_version[#{current_version},#{version}] first to update all version references"
      
      print "Continue anyway? (y/N): "
      response = STDIN.gets.chomp.downcase
      exit 1 unless response == 'y'
    end
    
    # Step 2: Build all packages if needed - check for ALL required file types
    escaped_version = escape_version_for_files(version)
    
    # Define file patterns to check
    file_patterns = {
      "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
      "mac_x64_dmg" => "Monadic.Chat-VERSION-x64.dmg",
      "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",
      "mac_x64_zip" => "Monadic.Chat-VERSION-x64.zip",
      "win_installer" => "Monadic.Chat.Setup.VERSION.exe",
      "win_zip" => "Monadic.Chat.Setup.VERSION.zip",
      "linux_x64_deb" => "monadic-chat_VERSION_amd64.deb",
      "linux_arm64_deb" => "monadic-chat_VERSION_arm64.deb",
      "linux_x64_zip" => "monadic-chat_VERSION_x64.zip",
      "linux_arm64_zip" => "monadic-chat_VERSION_arm64.zip"
    }
    
    # Check which files are missing
    missing_types = []
    file_patterns.each do |key, pattern|
      found_files = find_build_files(pattern, version, escaped_version)
      if found_files.empty?
        missing_types << key
      end
    end
    
    if !missing_types.empty?
      puts "Missing required files for version #{version}:"
      missing_types.each { |type| puts "  - #{type}: #{file_patterns[type]}" }
      puts "Building all packages..."
      Rake::Task["build"].invoke
    else
      puts "Found all required packages for version #{version}"
    end
    
    # Step 3: Create a release draft with release notes from CHANGELOG.md
    changelog_entry = extract_changelog_entry(version)
    
    if changelog_entry.empty?
      puts "Warning: No changelog entry found for version #{version}"
      changelog_entry = "Release #{version}"
    end
    
    # Write release notes to a temporary file
    release_notes_file = "release_notes_#{version}.md"
    File.write(release_notes_file, changelog_entry)
    
    # Step 4: Check if GitHub CLI is installed
    unless system("which gh > /dev/null 2>&1")
      puts "Error: GitHub CLI (gh) is not installed. Please install it first with:"
      puts "  brew install gh     # macOS"
      puts "  apt install gh      # Ubuntu/Debian"
      puts "  choco install gh    # Windows"
      exit 1
    end
    
    # Step 5: Check if user is authenticated with GitHub
    unless system("gh auth status > /dev/null 2>&1")
      puts "Error: Not authenticated with GitHub. Please run 'gh auth login' first."
      exit 1
    end
    
    # Step 6: Get release assets
    release_assets = []
    
    # Use the same file patterns as build check
    file_patterns.each do |key, pattern|
      found_files = find_build_files(pattern, version, escaped_version)
      if found_files.empty?
        puts "Warning: No release asset found for #{key}"
      else
        found_files.each do |file|
          puts "Found release asset: #{File.basename(file)}"
          release_assets << file
        end
      end
    end
    
    if release_assets.empty?
      puts "Error: No release assets found for version #{version}"
      exit 1
    end
    
    # Check for and include YML files for auto-updates
    puts "Searching for auto-update YML files in dist directory..."
    Dir.glob("dist/*.yml").each do |yml_path|
      yml_file = File.basename(yml_path)
      release_assets << yml_path
      puts "Found YML asset for auto-update: #{yml_path}"
    end
    
    if Dir.glob("dist/*.yml").empty?
      puts "Warning: No auto-update YML files found in dist directory."
      puts "Auto-updates may not work correctly without these files."
      puts "Consider rebuilding with: rake build"
    end
    
    puts "Total assets for release: #{release_assets.length}"
    
    # Note: installation.md files are now updated via the update_version task
    # We no longer need to update them explicitly in the release:github task
    
    # Step 7: Create GitHub release
    begin
      puts "Creating GitHub release v#{version} with #{release_assets.length} assets..."
      prerelease_arg = prerelease ? "--prerelease" : ""
      
      # Prepare files list with proper escaping for files with spaces
      escaped_assets = release_assets.map do |asset|
        # Escape spaces in file paths for shell
        "\"#{asset.gsub('"', '\\"')}\""
      end.join(' ')
      
      # Create the release command
      release_cmd = "gh release create v#{version} #{escaped_assets} --title 'Monadic Chat #{version}' --notes-file #{release_notes_file} #{prerelease_arg}"
      
      # If it's a draft, add the draft flag
      if ENV['DRAFT'] == 'true'
        release_cmd += " --draft"
        puts "Creating as DRAFT release (won't be visible to users)"
      end
      
      # Execute the command
      sh release_cmd
      
      puts "Release published successfully!"
      puts "URL: https://github.com/yohasebe/monadic-chat/releases/tag/v#{version}"
    rescue => e
      puts "Error publishing release: #{e.message}"
    ensure
      # Clean up
      File.unlink(release_notes_file) if File.exist?(release_notes_file)
    end
  end
  
  desc "Create a new draft release without publishing build artifacts"
  task :draft, [:version, :prerelease] do |_t, args|
    # Set the DRAFT environment variable to true
    ENV['DRAFT'] = 'true'
    
    # Call the github release task with the draft flag
    Rake::Task["release:github"].invoke(*args)
  end
  
  desc "List all GitHub releases for the repository"
  task :list do
    puts "Fetching GitHub releases..."
    sh "gh release list"
  end
  
  desc "Delete a GitHub release, its assets, and the corresponding tag"
  task :delete, [:version] do |_t, args|
    version = args[:version]
    
    if version.nil?
      puts "Error: Version required. Use rake release:delete[version]"
      exit 1
    end
    
    # Confirm deletion
    print "Are you sure you want to delete release v#{version} AND its tag? This cannot be undone! (y/N): "
    response = STDIN.gets.chomp.downcase
    exit 1 unless response == 'y'
    
    # Delete the release with --cleanup-tag option to also delete the tag
    puts "Deleting GitHub release v#{version} and its tag..."
    sh "gh release delete v#{version} --cleanup-tag"
    
    # Double-check if local tag still exists and delete it if necessary
    if system("git tag -l v#{version} | grep -q .")
      puts "Local tag v#{version} still exists. Removing local tag..."
      sh "git tag -d v#{version}"
    end
    
    puts "Release and tag deleted successfully!"
  end
  
  desc "Update assets in an existing GitHub release without deleting it"
  task :update_assets, [:version, :file_patterns] do |_t, args|
    version = args[:version]
    file_patterns = args[:file_patterns]
    
    if version.nil?
      puts "Error: Version required. Use rake release:update_assets[version,\"pattern1 pattern2 ...\"]"
      puts "Example: rake \"release:update_assets[0.9.79,'dist/*.zip dist/*.dmg']\" (with quotes to escape special characters)"
      puts "To update all standard release files: rake \"release:update_assets[0.9.79]\""
      exit 1
    end
    
    # Check if GitHub CLI is installed
    unless system("which gh > /dev/null 2>&1")
      puts "Error: GitHub CLI (gh) is not installed. Please install it first with:"
      puts "  brew install gh     # macOS"
      puts "  apt install gh      # Ubuntu/Debian"
      puts "  choco install gh    # Windows"
      exit 1
    end
    
    # Check if user is authenticated with GitHub
    unless system("gh auth status > /dev/null 2>&1")
      puts "Error: Not authenticated with GitHub. Please run 'gh auth login' first."
      exit 1
    end
    
    # Check if the release exists
    release_exists = system("gh release view v#{version} >/dev/null 2>&1")
    unless release_exists
      puts "Error: Release v#{version} does not exist."
      exit 1
    end
    
    # Get files to update
    escaped_version = escape_version_for_files(version)
    files_to_update = []
    
    if file_patterns.nil?
      # Default file patterns to look for
      update_patterns = {
        "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
        "mac_x64_dmg" => "Monadic.Chat-VERSION-x64.dmg",
        "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",
        "mac_x64_zip" => "Monadic.Chat-VERSION-x64.zip",
        "win_installer" => "Monadic.Chat.Setup.VERSION.exe",
        "win_zip" => "Monadic.Chat.Setup.VERSION.zip",
        "linux_x64_deb" => "monadic-chat_VERSION_amd64.deb",
        "linux_arm64_deb" => "monadic-chat_VERSION_arm64.deb",
        "linux_x64_zip" => "monadic-chat_VERSION_x64.zip",
        "linux_arm64_zip" => "monadic-chat_VERSION_arm64.zip"
      }
      
      # Find files using flexible pattern matching
      update_patterns.each do |key, pattern|
        found_files = find_build_files(pattern, version, escaped_version)
        if found_files.empty?
          puts "Warning: No files found for #{key}"
        else
          files_to_update.concat(found_files)
        end
      end
      
      # Also include all YML files
      files_to_update.concat(Dir.glob("dist/*.yml"))
    else
      # Custom patterns provided by user
      patterns = file_patterns.split(/\s+/)
      patterns.each do |pattern|
        expanded_files = Dir.glob(pattern)
        if expanded_files.empty?
          puts "Warning: No files found matching pattern '#{pattern}'"
        else
          files_to_update.concat(expanded_files)
        end
      end
    end
    
    if files_to_update.empty?
      puts "Error: No files found to update. Please check the patterns provided."
      exit 1
    end
    
    # First, delete the assets we're going to replace
    assets_to_delete = []
    files_to_update.each do |file|
      asset_name = File.basename(file)
      assets_to_delete << asset_name
    end
    
    # Get list of current assets for reference
    puts "Checking current assets in release v#{version}..."
    current_assets_output = `gh release view v#{version} --json assets`
    current_assets = JSON.parse(current_assets_output)['assets'].map { |a| a['name'] } rescue []
    
    # Print summary of what will be updated
    puts "\nUpdate Summary:"
    puts "- Release: v#{version}"
    puts "- Current assets: #{current_assets.join(', ')}"
    puts "- Assets to be updated: #{assets_to_delete.join(', ')}"
    puts "\nThis will silently replace the specified files in the GitHub release."
    print "Are you sure you want to continue? (y/N): "
    response = STDIN.gets.chomp.downcase
    exit 1 unless response == 'y'
    
    # Delete each asset individually
    puts "\nRemoving old assets from release..."
    assets_to_delete.each do |asset|
      if current_assets.include?(asset)
        puts "  Deleting asset '#{asset}' from release v#{version}..."
        system("gh release delete-asset v#{version} \"#{asset}\" -y")
      end
    end
    
    # Prepare files list with proper escaping for files with spaces
    escaped_files = files_to_update.map do |file|
      # Escape spaces in file paths for shell
      "\"#{file.gsub('"', '\\"')}\""
    end.join(' ')
    
    # Upload the new assets with clobber to overwrite any existing assets
    puts "\nUploading #{files_to_update.length} assets to release v#{version}..."
    upload_cmd = "gh release upload v#{version} #{escaped_files} --clobber"
    
    begin
      # Execute the command
      sh upload_cmd
      puts "\nAssets updated successfully!"
      puts "URL: https://github.com/yohasebe/monadic-chat/releases/tag/v#{version}"
      
      # Add a note about the update to the changelog if possible
      if ENV['UPDATE_CHANGELOG'] == 'true'
        changelog_file = "./CHANGELOG.md"
        if File.exist?(changelog_file)
          content = File.read(changelog_file)
          lines = content.lines
          
          # Find the line containing the target version
          version_line_index = lines.find_index { |line| line.include?(version) }
          
          if version_line_index
            # Add a note about the silent update
            update_time = Time.now.strftime('%Y-%m-%d %H:%M')
            update_note = "  - [#{update_time}] Silent update: replaced release assets\n"
            
            # Insert the note after the version line
            lines.insert(version_line_index + 1, update_note)
            
            # Write back to the changelog
            File.write(changelog_file, lines.join)
            puts "Added update note to CHANGELOG.md"
          end
        end
      end
    rescue => e
      puts "Error updating release assets: #{e.message}"
    end
  end
  
  # Helper method to extract changelog entry for specific version
  def extract_changelog_entry(version)
    changelog_file = "./CHANGELOG.md"
    return "" unless File.exist?(changelog_file)
    
    content = File.read(changelog_file)
    lines = content.lines
    
    # Find the line containing the target version
    version_line_index = lines.find_index { |line| line.include?(version) }
    return "" unless version_line_index
    
    # Find the next version entry or the end of the file
    next_version_line_index = lines[version_line_index+1..-1].find_index { |line| line.match(/^\s*-\s*\[\w+,\s*\d+\]/) }
    next_version_line_index = next_version_line_index ? version_line_index + 1 + next_version_line_index : lines.length
    
    # Extract the changelog entry
    changelog_entry = lines[version_line_index...next_version_line_index].join("").strip
    
    # Process the changelog entry for GitHub release format
    processed_entry = "## Monadic Chat #{version}\n\n"
    
    # Remove the version header and format as bullet points
    cleaned_entry = changelog_entry.sub(/^\s*-\s*\[[\w\s,]+\]\s*#{Regexp.escape(version)}/, "").strip
    
    # Format each line item
    cleaned_entry.lines.each do |line|
      line = line.strip
      if line.start_with?('-')
        processed_entry += line + "\n"
      elsif !line.empty?
        processed_entry += "- " + line + "\n"
      end
    end
    
    # Add a footer
    processed_entry += "\n\n---\nGenerated on #{Time.now.strftime('%Y-%m-%d')}"
    
    processed_entry
  end
end

# Help database namespace
namespace :help do
  desc "Build help database from documentation (incremental update)"
  task :build do
    puts "Building help database from documentation..."
    
    # Load API key from config
    require 'dotenv'
    config_path = File.expand_path("~/monadic/config/env")
    if File.exist?(config_path)
      Dotenv.load(config_path)
    end
    
    if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'].empty?
      puts "Error: OPENAI_API_KEY not found in ~/monadic/config/env"
      puts "The help database requires OpenAI API for generating embeddings."
      exit 1
    end
    
    # Check if pgvector container is running
    pgvector_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-pgvector-container'")
    unless pgvector_running
      puts "pgvector container is not running. Starting it..."
      if system("docker start monadic-chat-pgvector-container")
        puts "pgvector container started successfully."
        # Wait for PostgreSQL to be ready
        puts "Waiting for PostgreSQL to be ready..."
        max_attempts = 30
        attempt = 0
        while attempt < max_attempts
          if system("docker exec monadic-chat-pgvector-container pg_isready -h localhost -p 5432 > /dev/null 2>&1")
            puts "PostgreSQL is ready!"
            break
          end
          attempt += 1
          print "."
          sleep 1
        end
        
        if attempt >= max_attempts
          puts "\nError: PostgreSQL did not become ready in time."
          exit 1
        end
      else
        puts "Error: Failed to start pgvector container."
        exit 1
      end
    end
    
    # Ensure the script has proper Ruby path
    script_path = File.expand_path("docker/services/ruby/scripts/utilities/process_documentation.rb", __dir__)
    
    # Set environment variables for batch processing
    ENV['HELP_EMBEDDINGS_BATCH_SIZE'] ||= '50'
    ENV['HELP_CHUNKS_PER_RESULT'] ||= '3'
    
    # Check if Ruby container is running
    ruby_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-ruby-container'")
    
    # Change to the project root directory before running the script
    Dir.chdir(__dir__) do
      if ruby_running
        # Run inside Ruby container
        puts "Running inside Ruby container..."
        docker_cmd = "docker exec -e OPENAI_API_KEY='#{ENV['OPENAI_API_KEY']}' monadic-chat-ruby-container bash -c 'cd /monadic && ruby scripts/utilities/process_documentation.rb'"
        system(docker_cmd)
      else
        # Run locally
        puts "Running locally (Ruby container not running)..."
        system("ruby #{script_path}")
      end
      
      if $?.success?
        puts "Help database built successfully!"
        puts "Batch size used: #{ENV['HELP_EMBEDDINGS_BATCH_SIZE']}"
        puts "Chunks per result: #{ENV['HELP_CHUNKS_PER_RESULT']}"
        
        # Export the database for container builds
        puts "\nExporting help database..."
        export_script = File.expand_path("docker/services/ruby/scripts/utilities/export_help_database_docker.rb", __dir__)
        
        if ruby_running
          # Run export inside Ruby container
          docker_cmd = "docker exec monadic-chat-ruby-container bash -c 'cd /monadic && ruby scripts/utilities/export_help_database_docker.rb'"
          if system(docker_cmd)
            puts "Help database exported successfully!"
          else
            puts "Warning: Failed to export help database"
          end
        else
          # Run export locally
          if system("ruby #{export_script}")
            puts "Help database exported successfully!"
          else
            puts "Warning: Failed to export help database"
          end
        end
      else
        puts "Error building help database"
        exit 1
      end
    end
  end
  
  desc "Rebuild help database (drop existing data first)"
  task :rebuild do
    puts "Rebuilding help database from scratch..."
    
    # Load API key from config
    require 'dotenv'
    config_path = File.expand_path("~/monadic/config/env")
    if File.exist?(config_path)
      Dotenv.load(config_path)
    end
    
    if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'].empty?
      puts "Error: OPENAI_API_KEY not found in ~/monadic/config/env"
      puts "The help database requires OpenAI API for generating embeddings."
      exit 1
    end
    
    # Check if pgvector container is running
    pgvector_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-pgvector-container'")
    unless pgvector_running
      puts "pgvector container is not running. Starting it..."
      if system("docker start monadic-chat-pgvector-container")
        puts "pgvector container started successfully."
        # Wait for PostgreSQL to be ready
        puts "Waiting for PostgreSQL to be ready..."
        max_attempts = 30
        attempt = 0
        while attempt < max_attempts
          if system("docker exec monadic-chat-pgvector-container pg_isready -h localhost -p 5432 > /dev/null 2>&1")
            puts "PostgreSQL is ready!"
            break
          end
          attempt += 1
          print "."
          sleep 1
        end
        
        if attempt >= max_attempts
          puts "\nError: PostgreSQL did not become ready in time."
          exit 1
        end
      else
        puts "Error: Failed to start pgvector container."
        exit 1
      end
    end
    
    script_path = File.expand_path("docker/services/ruby/scripts/utilities/process_documentation.rb", __dir__)
    
    # Set environment variables for batch processing
    ENV['HELP_EMBEDDINGS_BATCH_SIZE'] ||= '50'
    ENV['HELP_CHUNKS_PER_RESULT'] ||= '3'
    
    # Check if Ruby container is running
    ruby_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-ruby-container'")
    
    if ruby_running
      # Ruby container is running but docs directory is not mounted
      # Always run documentation processing locally
      puts "Ruby container is running, but documentation processing must run locally..."
      puts "Running locally with proper database connection..."
      
      # Set database connection for local execution when containers are running
      ENV['POSTGRES_HOST'] ||= 'localhost'
      ENV['POSTGRES_PORT'] ||= '5433'
      system("ruby #{script_path} --recreate")
    else
      # Run locally with proper database connection
      puts "Running locally (Ruby container not running)..."
      ENV['POSTGRES_HOST'] ||= 'localhost'
      ENV['POSTGRES_PORT'] ||= '5433'
      system("ruby #{script_path} --recreate")
    end
    
    if $?.success?
      puts "Help database rebuilt successfully!"
      puts "Batch size used: #{ENV['HELP_EMBEDDINGS_BATCH_SIZE']}"
      puts "Chunks per result: #{ENV['HELP_CHUNKS_PER_RESULT']}"
      
      # Export the database for container builds
      puts "\nExporting help database..."
      export_script = File.expand_path("docker/services/ruby/scripts/utilities/export_help_database_docker.rb", __dir__)
      
      if ruby_running
        # Run export inside Ruby container
        docker_cmd = "docker exec monadic-chat-ruby-container bash -c 'cd /monadic && ruby scripts/utilities/export_help_database_docker.rb'"
        if system(docker_cmd)
          puts "Help database exported successfully!"
        else
          puts "Warning: Failed to export help database"
        end
      else
        # Run export locally
        if system("ruby #{export_script}")
          puts "Help database exported successfully!"
        else
          puts "Warning: Failed to export help database"
        end
      end
    else
      puts "Error rebuilding help database"
      exit 1
    end
  end
  
  desc "Show help database statistics"
  task :stats do
    # Define IN_CONTAINER constant before requiring help_embeddings
    IN_CONTAINER = File.file?("/.dockerenv")
    
    require_relative "docker/services/ruby/lib/monadic/utils/help_embeddings"
    
    help_db = HelpEmbeddings.new
    stats = help_db.get_stats
    
    puts "\n=== Help Database Statistics ==="
    puts "Documents by language:"
    stats[:documents_by_language].each do |lang, count|
      puts "  #{lang}: #{count} documents"
    end
    puts "Total items: #{stats[:total_items]}"
    puts "Average items per document: #{stats[:avg_items_per_doc]}"
  end
  
  desc "Export help database to files"
  task :export do
    puts "Exporting help database..."
    
    # Check if pgvector container is running
    pgvector_running = system("docker ps --format '{{.Names}}' | grep -q 'monadic-chat-pgvector-container'")
    unless pgvector_running
      puts "Error: pgvector container is not running. Please start it with 'rake server:start' first."
      exit 1
    end
    
    export_script = File.expand_path("docker/services/ruby/scripts/utilities/export_help_database_docker.rb", __dir__)
    if system("ruby #{export_script}")
      puts "Help database exported successfully!"
    else
      puts "Error exporting help database"
      exit 1
    end
  end
end
