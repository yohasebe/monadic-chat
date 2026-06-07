# frozen_string_literal: true

require "fileutils"
begin
  require "rspec/core/rake_task"
rescue LoadError
  # Allow listing/invoking non-RSpec tasks even if the gem isn't installed globally.
end
require "rubygems"
require_relative "./docker/services/ruby/lib/monadic/version"
version = Monadic::VERSION

# Unicode display width for proper terminal table alignment
begin
  require "unicode/display_width"
  UNICODE_DISPLAY_WIDTH_AVAILABLE = true
rescue LoadError
  UNICODE_DISPLAY_WIDTH_AVAILABLE = false
end

# Display-width-aware string padding helpers
# These methods pad strings based on terminal display width, not character count
module DisplayWidthHelpers
  def self.display_width(str)
    if UNICODE_DISPLAY_WIDTH_AVAILABLE
      Unicode::DisplayWidth.of(str)
    else
      str.length
    end
  end

  def self.ljust(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    str + (padstr * padding_needed)
  end

  def self.rjust(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    (padstr * padding_needed) + str
  end

  def self.center(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    left_pad = padding_needed / 2
    right_pad = padding_needed - left_pad
    (padstr * left_pad) + str + (padstr * right_pad)
  end
end

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

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new do |task|
    task.options = ["--config", "docker/services/ruby/.rubocop.yml"]
    task.patterns = ["docker/services/ruby/**/*.rb"]
  end
  task default: %i[spec rubocop]
rescue LoadError
  # RuboCop is not available, skip it
  task default: %i[spec]
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

    # Auto-rebuild the JS bundle if any frontend source is newer than the
    # bundled output. This prevents the common "I edited a JS file but my
    # changes don't show up" trap during development.
    bundle_path = File.expand_path("docker/services/ruby/public/js/monadic.bundle.min.js")
    if File.exist?(bundle_path)
      bundle_mtime = File.mtime(bundle_path)
      source_globs = [
        "docker/services/ruby/public/js/monadic/**/*.js",
        "docker/services/ruby/public/js/i18n/translations.js",
        "docker/services/ruby/public/js/debug-config.js"
      ]
      stale = source_globs.any? do |glob|
        Dir[File.expand_path(glob)].any? { |f| File.mtime(f) > bundle_mtime }
      end
      if stale
        puts "\n📦 JS sources changed since last bundle build — rebuilding..."
        sh "npm run build:js"
        puts
      end
    end

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

namespace :lint do
  desc "Check docs/translations for deprecated model names"
  task :deprecated_models do
    Dir.chdir(File.expand_path(__dir__)) do
      system('npm run lint:deprecated-models') || abort('Deprecated model lint failed')
    end
  end

  desc "Check model lifecycle consistency across codebase"
  task :model_consistency do
    Dir.chdir(File.expand_path(__dir__)) do
      system('npm run lint:model-consistency') || abort('Model consistency check failed')
    end
  end

  # Anti-pattern lint rules (see docs_dev/architecture_hardening_plan.md).
  # Each rule fails the build when its baseline is exceeded; the suite is
  # intentionally split so a partial green/red is still actionable.

  desc "Check that no personal home-directory paths leak into source"
  task :personal_paths do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/check_personal_paths.rb') ||
        abort('Personal path lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc "Check that shell-form interpolations escape user-controlled values"
  task :shell_escape do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/check_shell_escape.rb') ||
        abort('Shell escape lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc "Check that fetch() calls to xhr-dependent routes set X-Requested-With"
  task :xhr_pair do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/check_xhr_pair.rb') ||
        abort('XHR pair lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc 'Check that "/monadic/data" string literals stay inside the Environment helper'
  task :data_path_literals do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/check_data_path_literals.rb') ||
        abort('Data path literal lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc 'Check that bare ws.send(...) callsites stay inside the monadic-ws.js helper'
  task :bare_ws_send do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/check_bare_ws_send.rb') ||
        abort('Bare ws.send lint failed (see docs_dev/safe_ws_send_plan.md §3)')
    end
  end

  desc "Verify each anti-pattern lint still detects its target via temp fixture"
  task :self_check do
    Dir.chdir(File.expand_path(__dir__)) do
      system('ruby scripts/lint/spec/check_self_test.rb') ||
        abort('Lint self-check failed: at least one rule no longer detects its target. See scripts/lint/spec/check_self_test.rb')
    end
  end

  desc "Run every anti-pattern lint rule plus the self-check meta-test"
  task :anti_patterns => [:personal_paths, :shell_escape, :xhr_pair, :data_path_literals, :bare_ws_send, :self_check]
end

# Define the list of files that should have consistent version numbers
def version_files
  # Static files that always need version updates
  static_files = [
    "./docker/services/ruby/lib/monadic/version.rb",
    "./package.json",
    "./package-lock.json",
    "./docker/monadic.sh",
    "./docs/_coverpage.md",
    "./docs/ja/_coverpage.md",
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

    # Clean stale auto-update manifests from the previous build.
    #
    # electron-builder writes the platform-specific `latest*.yml` files
    # only for the architectures actually built in the current
    # invocation. A reduced-scope rebuild (e.g. `rake build:mac_arm64`
    # alone after a previous full build) leaves the manifests for
    # other archs/platforms untouched — the *file* survives with the
    # *previous* run's hashes. If those stale manifests are then
    # uploaded as part of the release, mac arm64 / linux / win
    # auto-updaters fetch a yml whose `sha512` no longer matches the
    # actual artifact, and the update silently fails with a hash
    # mismatch error.
    #
    # The actual artifacts (.dmg / .zip / .exe / .AppImage) are
    # regenerated by electron-builder, so leaving them alone is fine —
    # only the side-channel manifests need explicit cleanup.
    project_dist = File.join(File.dirname(__FILE__), "dist")
    if Dir.exist?(project_dist)
      Dir.glob(File.join(project_dist, "latest*.yml")).each do |f|
        puts "[setup_build_environment] Removing stale manifest: #{File.basename(f)}"
        FileUtils.rm_f(f)
      end
    end

    # Build and export help database unless skipped.
    #
    # Regenerates docker/services/ruby/help_data/help_db.json from docs/*
    # so the Electron bundle ships up-to-date help content. The dump is
    # consumed at runtime by Monadic::Help::DumpLoader, which imports it
    # into Qdrant on first start.
    #
    # The help:build task itself starts the embeddings_service container
    # if it is not already running and tears it down when done.
    unless skip_help_db
      puts "\n=== Building Help Database ==="
      Rake::Task["help:build"].invoke
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

    # electron-builder's mac `zip` target flattens framework symlinks, which
    # makes codesign report "bundle format is ambiguous (could be app or
    # framework)" and breaks Squirrel auto-update (beta.19, 2026-06-08).
    # Re-zip the intact .app with ditto BEFORE the manifest patch so the
    # patcher syncs the yml sha512/size to the corrected zip. The script
    # also codesign-verifies the result and fails the build if still broken.
    puts "[build:mac_arm64] Re-packaging macOS zip with preserved symlinks..."
    sh "ruby scripts/repackage_mac_zip.rb"

    # Single-arch arm64 builds (no companion x64) make electron-builder
    # emit only `latest-mac.yml`, not the arch-specific
    # `latest-mac-arm64.yml`. electron-updater on Apple Silicon checks
    # the arch-specific file first, so its absence (or, worse, a stale
    # copy from a multi-arch run) breaks auto-update. Mirror the freshly
    # written manifest as the arm64 channel file when only the canonical
    # one was generated. Done BEFORE the patch step so the patcher
    # treats both files uniformly.
    dist_dir = File.join(File.dirname(__FILE__), "dist")
    canonical = File.join(dist_dir, "latest-mac.yml")
    arm64_yml = File.join(dist_dir, "latest-mac-arm64.yml")
    if File.exist?(canonical) && !File.exist?(arm64_yml)
      FileUtils.cp(canonical, arm64_yml)
      puts "[build:mac_arm64] Mirrored latest-mac.yml -> latest-mac-arm64.yml"
    end

    # Patch every latest-mac*.yml so its `sha512` / `size` fields match
    # the actually-shipped (post-staple) DMG bytes. notarize-dmg.js
    # does this inside the afterAllArtifactBuild hook, but on some
    # electron-builder versions the yml is not yet populated with the
    # dmg entry at the moment that hook fires — the hook emits its
    # "no entry matched" warning and the yml is finalised later with
    # stale hashes. Running the patcher here, after `npm run` exits,
    # sidesteps the timing race because every artifact and every yml
    # are now on disk in their final form. Idempotent: if
    # notarize-dmg.js succeeded earlier, this is a no-op.
    #
    # 2026-05-12 regression note: a full 4-platform release build hit
    # the drift again even though this patch step was present, so the
    # block below adds an automatic retry: verify, and if it fails,
    # run patch + verify a second time. Patching is idempotent and
    # cheap, so the retry is free in the happy path.
    puts "[build:mac_arm64] Patching release manifests against shipped DMG bytes..."
    sh "ruby scripts/patch_release_manifests.rb"

    # Verify the post-staple manifest matches the shipped DMG bytes,
    # with one automatic patch+retry on failure as a safety net.
    puts "[build:mac_arm64] Verifying release manifests..."
    begin
      sh "ruby scripts/verify_release_manifests.rb"
    rescue RuntimeError => e
      warn "[build:mac_arm64] Initial verify failed (#{e.message.lines.first&.chomp})"
      warn "[build:mac_arm64] Re-running patch + verify before aborting..."
      sh "ruby scripts/patch_release_manifests.rb"
      sh "ruby scripts/verify_release_manifests.rb"
    end
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

  desc "Build macOS package (arm64 only, Apple Silicon)"
  task :mac => [:mac_arm64]

  desc "Build Linux packages (both x64 and arm64)"
  task :linux => [:linux_x64, :linux_arm64]

  desc "Verify every dist/latest*.yml matches its referenced artifact bytes"
  task :verify_manifests do
    sh "ruby scripts/verify_release_manifests.rb"
  end
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

    # macOS files (Apple Silicon only)
    "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
    "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",

    # Linux files (AppImage is the auto-update-compatible format)
    "linux_x64_appimage" => "monadic-chat_VERSION_x86_64.AppImage",
    "linux_arm64_appimage" => "monadic-chat_VERSION_arm64.AppImage"
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

  # Patch every latest-mac*.yml so its `sha512` / `size` fields match
  # the actually-shipped (post-staple) DMG bytes. Without this, the
  # macOS DMG entry stays on the *pre-staple* hash written by
  # electron-builder, and the verify step below fails. `build:mac_arm64`
  # has the same step; this top-level all-platform task needs it too
  # because user invocations (`rake build` vs `rake build:mac_arm64`)
  # take different code paths through this file.
  puts "\n=== Patching release manifests against shipped DMG bytes ==="
  sh "ruby scripts/patch_release_manifests.rb"

  # Final defense: verify every kept manifest matches its referenced
  # artifact byte-for-byte. Catches any future regression where a build
  # path bypasses notarize-dmg.js's post-staple manifest patch (or any
  # other source of drift between yml hashes and shipped bytes). One
  # automatic retry: idempotent patch + re-verify on first failure.
  puts "\n=== Verifying release manifests ==="
  begin
    sh "ruby scripts/verify_release_manifests.rb"
  rescue RuntimeError => e
    warn "[build] Initial verify failed (#{e.message.lines.first&.chomp})"
    warn "[build] Re-running patch + verify before aborting..."
    sh "ruby scripts/patch_release_manifests.rb"
    sh "ruby scripts/verify_release_manifests.rb"
  end
end

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

# =============================================================================
# API Media Tests (image/video/voice generation)
# =============================================================================
namespace :spec_api do
  desc "Real API media tests (image/video/voice). Requires RUN_MEDIA=true"
  task :media do
    ENV['RUN_API'] ||= 'true'
    ENV['RUN_MEDIA'] ||= 'true'
    ENV['API_TIMEOUT'] ||= '120'
    ENV['API_MAX_RETRIES'] ||= '0'
    ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
    Dir.chdir("docker/services/ruby") do
      fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
      sh "bundle exec rspec spec/integration/api_media #{fmt}"
    end
  end
end

# Test ruby code with rspec ./docker/services/ruby/spec
task :spec do
  # Set environment variables for test database connection
  # Set HOST_OS for Docker Compose
  ENV['HOST_OS'] ||= `uname -s`.chomp

  # Ensure qdrant + embeddings are running for any integration spec that
  # touches the vector store. Unit specs mock these and do not need them.
  qdrant_running = system("docker ps | grep -q monadic-chat-qdrant-container")
  embeddings_running = system("docker ps | grep -q monadic-chat-embeddings-container")

  if !qdrant_running || !embeddings_running
    puts "Starting qdrant + embeddings containers for tests..."
    compose_file = File.expand_path("docker/services/compose.yml", __dir__)
    qdrant_dev_file = File.expand_path("docker/services/qdrant/compose.dev.yml", __dir__)
    embeddings_dev_file = File.expand_path("docker/services/embeddings/compose.dev.yml", __dir__)
    project_dir = File.expand_path("docker/services", __dir__)

    overlays = [compose_file]
    overlays << qdrant_dev_file if File.exist?(qdrant_dev_file)
    overlays << embeddings_dev_file if File.exist?(embeddings_dev_file)
    files_arg = overlays.map { |f| "-f '#{f}'" }.join(' ')

    system("docker compose --project-directory '#{project_dir}' #{files_arg} -p 'monadic-chat' up -d qdrant_service embeddings_service")

    puts "Waiting for qdrant to be ready..."
    30.times do
      break if system("curl -sf http://localhost:6333/healthz >/dev/null 2>&1")
      sleep 1
    end
  end
  
  # Store paths before changing directory
  root_dir = __dir__
  
  # Run tests with the new structure
  ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
  Dir.chdir("docker/services/ruby") do
    fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
    puts "Running unit tests..."
    sh "bundle exec rspec spec/unit #{fmt} --no-fail-fast --no-profile"

    # Run integration tests if available
    puts "\nRunning integration tests..."
    sh "bundle exec rspec spec/integration #{fmt} --no-fail-fast --no-profile" rescue puts "Integration tests skipped (not available)"

    # Run system tests
    puts "\nRunning system tests..."
    sh "bundle exec rspec spec/system #{fmt} --no-fail-fast --no-profile" rescue puts "System tests skipped (not available)"
  end
ensure
  # Only stop qdrant + embeddings if we started them
  if (!qdrant_running || !embeddings_running) && ENV['KEEP_VECTOR_SERVICES'] != 'true'
    puts "Stopping qdrant + embeddings containers..."
    compose_file = File.expand_path("docker/services/compose.yml", root_dir)
    project_dir = File.expand_path("docker/services", root_dir)
    system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop qdrant_service embeddings_service")
  end
end

# Quick test task (unit + integration only, no media generation)
namespace :spec do
  desc "Run quick tests (unit + integration only, excludes system tests)"
  task :quick do
    # Set environment variables for test database connection
    ENV['POSTGRES_HOST'] ||= 'localhost'
    ENV['POSTGRES_PORT'] ||= '5433'
    ENV['POSTGRES_USER'] ||= 'postgres'
    ENV['POSTGRES_PASSWORD'] ||= 'postgres'

    # Set HOST_OS for Docker Compose
    ENV['HOST_OS'] ||= `uname -s`.chomp

    # Start qdrant + embeddings for tests that require them. Unit specs mock
    # these so they only matter for integration / system specs.
    qdrant_running = system("docker ps | grep -q monadic-chat-qdrant-container")
    embeddings_running = system("docker ps | grep -q monadic-chat-embeddings-container")

    if !qdrant_running || !embeddings_running
      puts "Starting qdrant + embeddings containers for tests..."
      compose_file = File.expand_path("docker/services/compose.yml", __dir__)
      qdrant_dev_file = File.expand_path("docker/services/qdrant/compose.dev.yml", __dir__)
      embeddings_dev_file = File.expand_path("docker/services/embeddings/compose.dev.yml", __dir__)
      project_dir = File.expand_path("docker/services", __dir__)

      overlays = [compose_file]
      overlays << qdrant_dev_file if File.exist?(qdrant_dev_file)
      overlays << embeddings_dev_file if File.exist?(embeddings_dev_file)
      files_arg = overlays.map { |f| "-f '#{f}'" }.join(' ')

      system("docker compose --project-directory '#{project_dir}' #{files_arg} -p 'monadic-chat' up -d qdrant_service embeddings_service")

      puts "Waiting for qdrant to be ready..."
      30.times do
        break if system("curl -sf http://localhost:6333/healthz >/dev/null 2>&1")
        sleep 1
      end
    end

    # Store paths before changing directory
    root_dir = __dir__

    # Run only unit and integration tests (exclude system tests)
    ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
    Dir.chdir("docker/services/ruby") do
      fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
      puts "Running unit tests..."
      sh "bundle exec rspec spec/unit #{fmt} --no-fail-fast --no-profile"

      # Run integration tests if available
      puts "\nRunning integration tests..."
      sh "bundle exec rspec spec/integration #{fmt} --no-fail-fast --no-profile" rescue puts "Integration tests skipped (not available)"

      puts "\n✅ Quick tests completed (system tests excluded)"
    end
  ensure
    # Only stop qdrant + embeddings if we started them
    if (!qdrant_running || !embeddings_running) && ENV['KEEP_VECTOR_SERVICES'] != 'true'
      puts "Stopping qdrant + embeddings containers..."
      compose_file = File.expand_path("docker/services/compose.yml", root_dir)
      project_dir = File.expand_path("docker/services", root_dir)
      system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop qdrant_service embeddings_service")
    end
  end
end

# Quick test task (Ruby quick + frontend)
namespace :test do
  desc "Run quick tests (Ruby unit+integration + npm test, no media generation)"
  task :quick do
    puts "=== Running Ruby quick tests ==="
    Rake::Task["spec:quick"].invoke

    puts "\n=== Running frontend tests ==="
    sh "npm test"

    puts "\n✅ All quick tests completed successfully!"
  end
end

# Unit test categories
namespace :spec_unit do
  desc "Run web search unit tests"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/openai_websearch_message_spec.rb spec/unit/websearch_tavily_config_spec.rb spec/unit/mistral_websearch_performance_spec.rb --format documentation"
    end
  end
end

# System test categories
namespace :spec_system do
  desc "Run web search system tests"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/system/chat_websearch_system_spec.rb spec/system/chat_websearch_update_spec.rb --format documentation"
    end
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
    # Check if native Ollama is running
    ollama_ok = system("curl -sf http://localhost:11434/ > /dev/null 2>&1")

    unless ollama_ok
      puts "\n" + "="*60
      puts "Ollama is not running"
      puts "="*60
      puts "\nPlease install and start Ollama before running tests."
      puts "\nInstall Ollama: https://ollama.com/download"
      puts "\nAfter installing, start it and pull a model:"
      puts "  ollama pull qwen3:4b"
      puts "="*60 + "\n"
      exit 0
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
  
  desc "Run E2E tests for Web Insight"
  task :web_insight do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh web_insight"
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
  
  desc "Run E2E tests for Chat Export/Import functionality"
  task :chat_export_import do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat_export_import"
    end
  end
  
  desc "Run E2E tests for Chat Plus Monadic functionality"
  task :chat_plus_monadic_test do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat_plus_monadic_test"
    end
  end
  
  desc "Run E2E tests for web search functionality"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh websearch"
    end
  end
end

# Test JavaScript code with Jest
desc "Run JavaScript tests using Jest"
task :jstest, [:save_results, :output_dir] do |_t, args|
  require 'fileutils'
  require 'time'

  # Determine if we should save results
  save = args[:save_results] == 'true' || ENV['JEST_SAVE_RESULTS'] == 'true'
  output_dir = args[:output_dir] || ENV['JEST_OUTPUT_DIR']

  if save && output_dir
    # output_dir is the unified test results directory
    FileUtils.mkdir_p(output_dir)
    json_file = File.join(output_dir, 'jest.json')
    puts "Running Jest tests (saving results to #{json_file})..."

    success = system("npm test -- --json --outputFile=#{json_file}")

    if File.exist?(json_file)
      puts "✅ Jest results saved to: #{json_file}"
    else
      puts "⚠️  Warning: Jest results file was not created"
    end

    exit 1 unless success
  elsif save
    # Fallback: save to flat file with timestamp
    results_dir = File.expand_path('tmp/test_results', __dir__)
    FileUtils.mkdir_p(results_dir)
    run_id = Time.now.strftime('%Y%m%d_%H%M%S')
    json_file = File.join(results_dir, "jest_#{run_id}.json")
    puts "Running Jest tests (saving results to #{json_file})..."

    success = system("npm test -- --json --outputFile=#{json_file}")

    if File.exist?(json_file)
      puts "✅ Jest results saved to: #{json_file}"
    else
      puts "⚠️  Warning: Jest results file was not created"
    end

    exit 1 unless success
  else
    sh "npm test"
  end
end

# For backward compatibility
desc "Run all JavaScript tests using Jest"
task :jstest_all => :jstest

# Test Python code
namespace :pytest do
  desc "Run all Python tests"
  task :all, [:save_results, :output_dir] do |_t, args|
    require 'fileutils'
    require 'time'
    require 'open3'

    # Determine if we should save results
    save = args[:save_results] == 'true' || ENV['PYTEST_SAVE_RESULTS'] == 'true'
    output_dir = args[:output_dir] || ENV['PYTEST_OUTPUT_DIR']

    puts "Running Python tests..."
    python_test_dirs = [
      "docker/services/python/scripts/services"
    ]

    all_output = []
    all_success = true

    python_test_dirs.each do |dir|
      if Dir.exist?(dir)
        puts "\nRunning tests in #{dir}..."
        Dir.chdir(dir) do
          # Run all test files
          test_files = Dir.glob("test_*.py")
          if test_files.any?
            test_files.each do |test_file|
              puts "Running #{test_file}..."
              stdout, stderr, status = Open3.capture3("python3", test_file, "-v")
              output = "=== #{test_file} ===\n#{stdout}\n#{stderr}"
              all_output << output
              puts output

              unless status.success?
                puts "Test failed: #{test_file}"
                all_success = false
              end
            end
          else
            puts "No test files found in #{dir}"
            all_output << "No test files found in #{dir}"
          end
        end
      end
    end

    # Save results if requested
    if save && output_dir
      # output_dir is the unified test results directory
      FileUtils.mkdir_p(output_dir)
      output_file = File.join(output_dir, 'pytest.txt')
      File.write(output_file, all_output.join("\n\n"))
      puts "\n✅ Python test results saved to: #{output_file}"
    elsif save
      # Fallback: save to flat file with timestamp
      results_dir = File.expand_path('tmp/test_results', __dir__)
      FileUtils.mkdir_p(results_dir)
      run_id = Time.now.strftime('%Y%m%d_%H%M%S')
      output_file = File.join(results_dir, "pytest_#{run_id}.txt")
      File.write(output_file, all_output.join("\n\n"))
      puts "\n✅ Python test results saved to: #{output_file}"
    end

    exit 1 unless all_success
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
task :test do
  require 'time'
  require 'fileutils'
  require 'json'

  # Generate unified run ID for this test session
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  run_id = "test_#{timestamp}"

  # Create unified output directory
  output_dir = File.expand_path("tmp/test_results/#{run_id}", __dir__)
  FileUtils.mkdir_p(output_dir)

  puts "=" * 60
  puts "Running all tests (Ruby, JavaScript, Python)"
  puts "Run ID: #{run_id}"
  puts "Output: #{output_dir}/"
  puts "=" * 60

  results = {}
  start_time = Time.now

  # Run Ruby tests
  puts "\n[1/3] Running Ruby tests..."
  results[:ruby] = Rake::Task[:spec].invoke

  # Run JavaScript tests with result saving
  puts "\n[2/3] Running JavaScript tests..."
  Rake::Task[:jstest].reenable
  results[:javascript] = Rake::Task[:jstest].invoke('true', output_dir)

  # Run Python tests with result saving
  puts "\n[3/3] Running Python tests..."
  Rake::Task["pytest:all"].reenable
  results[:python] = Rake::Task["pytest:all"].invoke('true', output_dir)

  duration = Time.now - start_time
  all_passed = results.values.all?

  # Write combined summary
  summary = {
    run_id: run_id,
    timestamp: timestamp,
    duration: duration.round(2),
    results: results,
    overall_status: all_passed ? 'passed' : 'failed'
  }
  File.write(File.join(output_dir, 'summary.json'), JSON.pretty_generate(summary))

  # Create symlink to latest
  latest_link = File.expand_path('tmp/test_results/latest', __dir__)
  FileUtils.rm_f(latest_link)
  FileUtils.ln_sf(output_dir, latest_link)

  puts "\n" + "=" * 60
  puts all_passed ? "✅ ALL TESTS COMPLETED" : "⚠️  SOME TESTS MAY HAVE FAILED"
  puts "=" * 60
  puts "Duration: #{duration.round(2)}s"
  puts "Results saved to: #{output_dir}/"
  puts "  - jest.json (JavaScript)"
  puts "  - pytest.txt (Python)"
  puts "  - summary.json (Combined)"
  puts "=" * 60
end

# Run only the jupyter controller integration test
desc "Run Jupyter controller integration test"
task :jupyter_integration do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/integration/jupyter_controller_integration_spec.rb --format documentation"
  end
end

# Test summary utilities
namespace :test_summary do
  desc "Print a concise summary from the latest tmp/test_runs/*/rspec_report.json"
  task :latest do
    require 'json'
    require 'time'
    base = File.expand_path('tmp/test_runs', __dir__)
    unless Dir.exist?(base)
      puts "No test_runs directory found at #{base}"
      next
    end
    # Find latest directory by timestamp
    candidates = Dir.glob(File.join(base, '*/rspec_report.json')).sort
    if candidates.empty?
      puts "No rspec_report.json found under #{base}"
      next
    end
    path = candidates.last
    print_summary_from(path)
  end

  desc "Print a concise summary from a specific rspec_report.json path"
  task :path, [:json_path] do |_t, args|
    require 'json'
    path = args[:json_path]
    unless path && File.exist?(path)
      puts "Provide a valid path: rake test_summary:path[./tmp/test_runs/<ts>/rspec_report.json]"
      next
    end
    print_summary_from(path)
  end

  def print_summary_from(path)
    require 'json'
    data = JSON.parse(File.read(path))
    c = data['counts'] || {}
    dur = data['duration_seconds'] || 0
    seed = data['seed']
    puts "Counts: total=#{c['total']} passed=#{c['passed']} failed=#{c['failed']} pending=#{c['pending']} duration=#{dur}s seed=#{seed}"
    examples = data['examples'] || []
    failed = examples.select { |e| e['status'] == 'failed' }
    pend   = examples.select { |e| e['status'] == 'pending' }
    if failed.any?
      puts "\nFailed (#{failed.size}):"
      failed.first(50).each_with_index do |e, i|
        loc = "#{e['file_path']}:#{e['line_number']}"
        msg = e.dig('exception', 'message')
        puts sprintf("%2d. %s — %s — %s", i+1, e['description'], loc, msg)
      end
    end
    if pend.any?
      puts "\nPending (#{pend.size}):"
      pend.first(50).each_with_index do |e, i|
        loc = "#{e['file_path']}:#{e['line_number']}"
        msg = e['pending_message']
        puts sprintf("%2d. %s — %s — %s", i+1, e['description'], loc, msg)
      end
    end
    puts "\nSource: #{path}"
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
    
    # Define file patterns to check (macOS is Apple Silicon only; Linux uses AppImage)
    file_patterns = {
      "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
      "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",
      "win_installer" => "Monadic.Chat.Setup.VERSION.exe",
      "win_zip" => "Monadic.Chat.Setup.VERSION.zip",
      "linux_x64_appimage" => "monadic-chat_VERSION_x86_64.AppImage",
      "linux_arm64_appimage" => "monadic-chat_VERSION_arm64.AppImage"
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
      # macOS is Apple Silicon only
      update_patterns = {
        "mac_arm64_dmg" => "Monadic.Chat-VERSION-arm64.dmg",
        "mac_arm64_zip" => "Monadic.Chat-VERSION-arm64.zip",
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
    
    # Find the version's header line. Anchor on the "- [Month, Year] <version>"
    # heading shape (not a bare substring match) so a body line that merely
    # mentions the version string — e.g. a prior release noting it was
    # "superseded by 1.0.0-beta.18" — cannot be picked up as the section start.
    # The trailing (?![\w.]) boundary stops "beta.18" from also matching a
    # future "beta.18.1" heading.
    header_re = /^\s*-\s*\[[\w\s,]+\]\s*#{Regexp.escape(version)}(?![\w.])/
    version_line_index = lines.find_index { |line| line.match(header_re) }
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

# Help database namespace
namespace :help do
  # Help database build pipeline.
  #
  # The runtime app does NOT need this to run — it consumes the prebuilt
  # JSON dump baked into the Ruby image at docker/services/ruby/help_data/.
  # These tasks regenerate that dump from docs/*.md (and docs_dev/*.md when
  # internal docs are requested) using the embeddings_service container.

  HELP_BUILD_SCRIPT = File.expand_path(
    'docker/services/ruby/scripts/utilities/process_documentation.rb', __dir__
  )

  HELP_DATA_DUMP = File.expand_path(
    'docker/services/ruby/help_data/help_db.json', __dir__
  )

  # Ensure the embeddings_service container is up before invoking the script.
  # Returns true if it was newly started (so the caller knows to stop it),
  # or false if it was already running.
  def ensure_embeddings_service
    if system("docker ps --format '{{.Names}}' | grep -q '^monadic-chat-embeddings-container$'")
      return false
    end

    puts 'Starting embeddings container...'
    compose_file = File.expand_path('docker/services/compose.yml', __dir__)
    embeddings_dev = File.expand_path('docker/services/embeddings/compose.dev.yml', __dir__)
    project_dir = File.expand_path('docker/services', __dir__)
    overlays = ["-f '#{compose_file}'"]
    overlays << "-f '#{embeddings_dev}'" if File.exist?(embeddings_dev)
    system("docker compose --project-directory '#{project_dir}' #{overlays.join(' ')} -p 'monadic-chat' up -d embeddings_service")

    print 'Waiting for embeddings service '
    60.times do
      if system('curl -sf http://localhost:8002/v1/health >/dev/null 2>&1')
        puts ' ready.'
        return true
      end
      print '.'
      sleep 1
    end
    puts ' (timeout)'
    raise 'embeddings_service did not become ready in 60s'
  end

  desc 'Build help database JSON dump from docs/* (includes internal docs)'
  task :build do
    started = ensure_embeddings_service
    # The script depends on the `http` gem, which lives only in
    # docker/services/ruby/Gemfile (the project-root Gemfile is minimal).
    # with_unbundled_env clears the parent BUNDLE_GEMFILE so the inner
    # `bundle exec` resolves against docker/services/ruby/Gemfile.
    # The explicit require handles plain `rake build:mac_arm64` invocations
    # where Bundler is not autoloaded (only `bundle exec rake` autoloads it).
    require 'bundler'
    Bundler.with_unbundled_env do
      Dir.chdir(File.expand_path('docker/services/ruby', __dir__)) do
        sh "bundle exec ruby '#{HELP_BUILD_SCRIPT}' --include-internal"
      end
    end
    if started && ENV['KEEP_VECTOR_SERVICES'] != 'true'
      compose_file = File.expand_path('docker/services/compose.yml', __dir__)
      project_dir = File.expand_path('docker/services', __dir__)
      system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop embeddings_service")
    end
  end

  desc '[DEPRECATED] Use rake help:build instead'
  task :build_dev do
    warn '[help:build_dev] deprecated; redirecting to help:build.'
    Rake::Task['help:build'].invoke
  end

  desc 'Rebuild help database JSON dump from scratch'
  task :rebuild do
    File.delete(HELP_DATA_DUMP) if File.exist?(HELP_DATA_DUMP)
    Rake::Task['help:build'].invoke
  end

  desc 'Show help database dump statistics'
  task :stats do
    unless File.exist?(HELP_DATA_DUMP)
      puts 'No help DB dump found. Run rake help:build first.'
      exit 1
    end
    require 'json'
    data = JSON.parse(File.read(HELP_DATA_DUMP))
    puts "Help DB dump: #{HELP_DATA_DUMP}"
    puts "Version:           #{data['version']}"
    puts "Embedding model:   #{data['embedding_model']}"
    puts "Dimension:         #{data['embedding_dimension']}"
    puts "Exported at:       #{data['exported_at']}"
    (data['collections'] || {}).each do |name, contents|
      puts "Collection #{name}: #{(contents['points'] || []).size} points"
    end
  end

  desc 'Show the path of the help database dump'
  task :export do
    puts HELP_DATA_DUMP
    exit(File.exist?(HELP_DATA_DUMP) ? 0 : 1)
  end
end

# Model specification synchronization tasks
namespace :models do
  desc "Check model specification synchronization with provider APIs"
  task :check do
    puts "Checking model specification synchronization..."
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb:297 --format documentation"
    end
  end
  
  desc "Run full model specification validation tests"
  task :validate do
    puts "Running full model specification validation tests..."
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb --format documentation"
    end
  end
  
  desc "Generate a summary report of model synchronization status"
  task :report do
    puts "\n" + "=" * 80
    puts "MODEL SPECIFICATION SYNCHRONIZATION REPORT"
    puts "=" * 80
    puts "\nThis report shows which models need to be added or removed from model_spec.js"
    puts "to stay synchronized with each provider's API.\n\n"
    
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb:297 --format progress 2>/dev/null | grep -E '(✓|⚠️|✅|Models in|Missing|deprecated)'"
    end
    
    puts "\n" + "=" * 80
    puts "To update model_spec.js, edit: docker/services/ruby/public/js/monadic/model_spec.js"
    puts "=" * 80
  end
  
  desc "Test custom models loading system"
  task :test_custom do
    puts "\n" + "=" * 80
    puts "CUSTOM MODELS SYSTEM TESTS"
    puts "=" * 80
    
    Dir.chdir("docker/services/ruby") do
      puts "\n📝 Running unit tests for ModelSpecLoader..."
      sh "bundle exec rspec spec/unit/model_spec_loader_spec.rb --format documentation"
      
      puts "\n📝 Running unit tests for API endpoint..."
      sh "bundle exec rspec spec/unit/api_models_endpoint_spec.rb --format documentation"
      
      puts "\n📝 Running integration tests..."
      sh "bundle exec rspec spec/integration/model_spec_loader_integration_spec.rb --format documentation"
    end
    
    puts "\n" + "=" * 80
    puts "✅ All custom models system tests completed!"
    puts "=" * 80
  end
  
  desc "Test all model-related functionality"
  task :test_all => [:validate, :test_custom] do
    puts "\n" + "=" * 80
    puts "✅ All model tests completed successfully!"
    puts "=" * 80
  end
end
# -----------------------------------------------------------------------------
# Unified Test Runner tasks (developer UX)
# -----------------------------------------------------------------------------
namespace :test do
  desc "Show available test suites and options"
  task :help do
    require_relative 'lib/test_runner'
    TestRunner.show_help
  end

  desc "Run tests with user-friendly interface"
  task :run, [:suite, :options] do |_t, args|
    require_relative 'lib/test_runner'
    runner = TestRunner.new(args[:suite], args[:options])
    runner.execute
  end

  desc "Run tests using predefined profile from config/test/test-config.yml (fallback: .test-config.yml)"
  task :profile, [:name] do |_t, args|
    require 'yaml'
    require_relative 'lib/test_runner'
    # Prefer new path, fall back to legacy path for backward compatibility
    config_path = ENV['TEST_PROFILE_PATH'] || 'config/test/test-config.yml'
    unless File.exist?(config_path)
      legacy = '.test-config.yml'
      if File.exist?(legacy)
        config_path = legacy
        puts "[test:profile] Using legacy profile path: #{legacy}"
      else
        puts "Profile config not found: #{config_path} (or #{legacy})"
        exit 1
      end
    end
    cfg = YAML.safe_load(File.read(config_path)) || {}
    profiles = cfg['profiles'] || {}
    profile = profiles[args[:name]]
    if profile.nil?
      puts "Profile '#{args[:name]}' not found"
      puts "Available profiles: #{profiles.keys.join(', ')}"
      exit 1
    end
    suites = profile['suites'] || []
    common_opts = profile.reject { |k, _| k == 'suites' }
    suites.each do |suite|
      options_str = common_opts.map { |k, v| "#{k}=#{Array(v).join(',')}" }.join(',')
      Rake::Task['test:run'].invoke(suite, options_str)
      Rake::Task['test:run'].reenable
    end
  end

  desc "List recent test results"
  task :history, [:count] do |_t, args|
    require_relative 'lib/test_runner'
    TestRunner.show_history((args[:count] || 10).to_i)
  end

  desc "Compare two test runs (by run_id)"
  task :compare, [:run1, :run2] do |_t, args|
    require_relative 'lib/test_runner'
    TestRunner.compare_runs(args[:run1], args[:run2])
  end

  desc "Clean up old test results (keep latest N, default: 3)"
  task :cleanup, [:keep_count] do |_t, args|
    require 'fileutils'

    keep_count = (args[:keep_count] || ENV['TEST_KEEP_COUNT'] || '3').to_i
    results_dir = File.expand_path('tmp/test_results', __dir__)

    unless Dir.exist?(results_dir)
      puts "No test results directory found at #{results_dir}"
      next
    end

    # Get all timestamped directories (YYYYMMDD_HHMMSS format)
    dirs = Dir.glob(File.join(results_dir, '2*')).select { |f| File.directory?(f) }

    # Sort by modification time (newest first)
    sorted_dirs = dirs.sort_by { |d| File.mtime(d) }.reverse

    # Get directories and files to delete
    to_delete_dirs = sorted_dirs[keep_count..-1] || []

    # Also clean up orphaned files (jest.json, pytest.txt, etc.)
    all_files = Dir.glob(File.join(results_dir, '*')).select { |f| File.file?(f) }

    # Keep files associated with kept directories and summary files
    kept_run_ids = sorted_dirs[0...keep_count].map { |d| File.basename(d) }
    to_delete_files = all_files.reject do |f|
      basename = File.basename(f)
      # Keep latest symlink, summary files, and files matching kept run IDs
      basename == 'latest' ||
      basename.start_with?('summary_') ||
      basename.start_with?('index_') ||
      kept_run_ids.any? { |id| basename.include?(id) }
    end

    if to_delete_dirs.empty? && to_delete_files.empty?
      puts "No old test results to clean up (keeping latest #{keep_count})"
      next
    end

    puts "Cleaning up old test results (keeping latest #{keep_count})..."

    deleted_count = 0
    to_delete_dirs.each do |dir|
      puts "  Deleting: #{File.basename(dir)}/"
      FileUtils.rm_rf(dir)
      deleted_count += 1
    end

    to_delete_files.each do |file|
      puts "  Deleting: #{File.basename(file)}"
      FileUtils.rm_f(file)
      deleted_count += 1
    end

    puts "✅ Cleaned up #{deleted_count} items"
    puts "Kept #{sorted_dirs.size - to_delete_dirs.size} recent test results"
  end

  desc "Run all tests (Ruby, JavaScript, Python) with unified runner"
  task :all, [:api_level, :open] do |_t, args|
    require_relative 'lib/test_runner'
    require 'json'
    require 'fileutils'

    api_level = args[:api_level] || ENV['TEST_API_LEVEL'] || 'standard'
    want_open = (args[:open].to_s == 'true' || ENV['OPEN_INDEX'] == 'true')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    run_id = timestamp

    # Create unified output directory for all test results
    output_dir = File.expand_path("tmp/test_results/#{run_id}", __dir__)
    FileUtils.mkdir_p(output_dir)

    # Set TEST_OUTPUT_DIR so RSpec SummaryFormatter uses this directory
    ENV['TEST_OUTPUT_DIR'] = output_dir

    # Pre-check: Docker daemon must be running for Ruby tests
    docker_check = system("docker info > /dev/null 2>&1")
    unless docker_check
      puts "\n❌ Docker daemon is not running!"
      puts "   Please start Docker Desktop before running tests."
      puts "   (JavaScript and Python tests do not require Docker)\n\n"
      exit 1
    end

    # Determine what tests to run based on api_level
    run_media = (api_level == 'full')
    run_websearch = (api_level == 'full')

    # Set environment variables for test runs
    if api_level == 'full'
      ENV['RUN_MEDIA'] = 'true'
      ENV['RUN_WEBSEARCH_TESTS'] = 'true'
      ENV['RUN_API'] = 'true'
    elsif api_level == 'standard'
      ENV['RUN_API'] = 'true'
    end

    # Calculate total steps
    total_steps = 5  # unit, integration, system, javascript, python
    total_steps += 1 if api_level != 'none'  # api tests
    total_steps += 1 if run_media             # media tests
    total_steps += 1 if run_websearch         # websearch tests

    # Build banner with proper display-width alignment
    banner_width = 42  # Inner width between ║ characters
    puts "╔#{'═' * banner_width}╗"
    puts "║#{DisplayWidthHelpers.center('Monadic Chat - Full Test Suite', banner_width)}║"
    puts "║   API Level: #{DisplayWidthHelpers.ljust(api_level, banner_width - 14)}║"
    puts "║   Media Tests: #{DisplayWidthHelpers.ljust(run_media ? 'enabled' : 'disabled', banner_width - 16)}║"
    puts "║   Websearch Tests: #{DisplayWidthHelpers.ljust(run_websearch ? 'enabled' : 'disabled', banner_width - 20)}║"
    puts "║   Output: #{DisplayWidthHelpers.ljust(run_id, banner_width - 11)}║"
    puts "╚#{'═' * banner_width}╝"

    results = {}
    start_time = Time.now
    step = 0

    # Ruby unit tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby unit tests..."
    unit_json = File.join(output_dir, 'unit.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_unit] = system("bundle exec rspec spec/unit --format documentation --format json --out #{unit_json}")
    end

    # Ruby integration tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby integration tests..."
    integration_json = File.join(output_dir, 'integration.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_integration] = system("bundle exec rspec spec/integration --format documentation --format json --out #{integration_json}")
    end

    # Ruby system tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby system tests..."
    system_json = File.join(output_dir, 'system.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_system] = system("bundle exec rspec spec/system --format documentation --format json --out #{system_json}")
    end

    # API tests (optional by level)
    if api_level != 'none'
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running API tests..."
      api_json = File.join(output_dir, 'api.json')
      Dir.chdir("docker/services/ruby") do
        results[:api] = system("bundle exec rspec spec/integration --tag api --format documentation --format json --out #{api_json}")
      end
    else
      results[:api] = true
    end

    # Media tests (only on 'full' API level)
    if run_media
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running Media tests (image/video/audio generation)..."
      media_json = File.join(output_dir, 'media.json')
      Dir.chdir("docker/services/ruby") do
        results[:media] = system("bundle exec rspec spec/integration/api_media --format documentation --format json --out #{media_json}")
      end
    else
      results[:media] = true
    end

    # Websearch API tests (only on 'full' API level)
    if run_websearch
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running Websearch API tests..."
      websearch_json = File.join(output_dir, 'websearch.json')
      Dir.chdir("docker/services/ruby") do
        # Run websearch-tagged integration tests
        results[:websearch] = system("bundle exec rspec spec/integration --tag websearch --format documentation --format json --out #{websearch_json}")
      end
    else
      results[:websearch] = true
    end

    # JavaScript tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running JavaScript tests..."
    # Use system() to run as subprocess - invoke() returns task object, not result
    results[:javascript] = system("rake 'jstest[true,#{output_dir}]'")

    # Python tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Python tests..."
    # Use system() to run as subprocess - invoke() returns task object, not result
    results[:python] = system("rake 'pytest:all[true,#{output_dir}]'")

    duration = Time.now - start_time
    all_passed = results.values.all?

    # Write combined summary
    summary = {
      run_id: run_id,
      api_level: api_level,
      timestamp: timestamp,
      duration: duration.round(2),
      results: results,
      overall_status: all_passed ? 'passed' : 'failed'
    }
    File.write(File.join(output_dir, 'summary.json'), JSON.pretty_generate(summary))

    # Create symlink to latest
    latest_link = File.expand_path('tmp/test_results/latest', __dir__)
    FileUtils.rm_f(latest_link)
    FileUtils.ln_sf(output_dir, latest_link)

    # Generate a simple index HTML bundling suite reports
    begin
      require_relative 'lib/test_index_html'
      suites = []
      suites << { name: :unit,        file: 'unit.json',        status: results[:ruby_unit] }
      suites << { name: :integration, file: 'integration.json', status: results[:ruby_integration] }
      suites << { name: :system,      file: 'system.json',      status: results[:ruby_system] }
      suites << { name: :api,         file: 'api.json',         status: results[:api] } if api_level != 'none'
      suites << { name: :media,       file: 'media.json',       status: results[:media] } if run_media
      suites << { name: :websearch,   file: 'websearch.json',   status: results[:websearch] } if run_websearch
      suites << { name: :javascript,  file: 'jest.json',        status: results[:javascript] }
      suites << { name: :python,      file: 'pytest.txt',       status: results[:python] }
      idx_path = File.join(output_dir, 'index.html')
      TestIndexHTML.generate_unified(output_dir, run_id, suites, idx_path)
      puts "\n📄 Index report generated: #{idx_path}"
      if want_open
        if RUBY_PLATFORM =~ /darwin/i
          system("open", idx_path)
        else
          puts "(Auto-open is only supported on macOS; skipping)"
        end
      end
    rescue StandardError => e
      puts "⚠️  Could not generate index HTML: #{e.message}"
    end

    puts "\n" + "=" * 50
    puts all_passed ? "✅ ALL TESTS PASSED!" : "❌ SOME TESTS FAILED"
    puts "=" * 50
    puts "Duration: #{duration.round(2)}s"
    puts "Results saved to: #{output_dir}/"

    if !all_passed
      failed = results.select { |_, v| !v }.keys
      puts "\nFailed components: #{failed.join(', ')}"
    end

    exit(all_passed ? 0 : 1)
  end

  desc "Run quick smoke tests (subset of all tests)"
  task :smoke, [:api_level] do |_t, args|
    api_level = args[:api_level] || 'none'
    puts "🚬 Running smoke tests (api_level=#{api_level})..."
    system("rake test:run[unit,\"api_level=#{api_level},focus=critical\"]")
  end

  desc "Run JavaScript tests via unified runner"
  task :js do
    require_relative 'lib/test_runner'
    TestRunner.new('js').execute
  end

  desc "Run Python tests via unified runner"
  task :python do
    require_relative 'lib/test_runner'
    TestRunner.new('python').execute
  end

  desc "Analyze last test run results and extract failures/pending"
  task :analyze, [:run_id] do |_t, args|
    require 'json'
    require_relative 'lib/test_result_analyzer'
    run_id = args[:run_id]
    if run_id.nil?
      latest = Dir.glob('tmp/test_results/*_meta.json').max_by { |f| File.mtime(f) }
      run_id = latest && File.basename(latest).sub(/_meta\.json\z/, '')
    end
    if run_id.nil?
      puts 'No test results found'
      next
    end
    json_path = File.join('tmp', 'test_results', "#{run_id}.json")
    TestResultAnalyzer.analyze_and_save(json_path, run_id)
    puts "Analysis complete for #{run_id}"
  end

  desc "Generate HTML report for a test run (default: latest)"
  task :report, [:run_id, :out] do |_t, args|
    require 'fileutils'
    require_relative 'lib/test_report_html'
    results_dir = File.join('tmp', 'test_results')
    FileUtils.mkdir_p(results_dir)
    run_id = args[:run_id]
    if run_id.nil?
      latest = Dir.glob(File.join(results_dir, '*_meta.json')).max_by { |f| File.mtime(f) }
      run_id = latest && File.basename(latest).sub(/_meta\.json\z/, '')
    end
    if run_id.nil?
      puts 'No test results found'
      next
    end
    out = args[:out] || File.join(results_dir, "report_#{run_id}.html")
    path = TestReportHTML.generate(results_dir, run_id, out)
    puts "HTML report generated: #{path}"
  end
end
