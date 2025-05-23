# frozen_string_literal: true

require "fileutils"
require "rspec/core/rake_task"
require_relative "./docker/services/ruby/lib/monadic/version"
version = Monadic::VERSION

RSpec::Core::RakeTask.new(:spec)

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
    
    # Replace version in the GitHub release path
    updated_content = content.gsub(/\/v#{Regexp.escape(from_version)}\//, "/v#{to_version}/")
    
    # Replace version in file names for all platforms
    # Mac files
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(from_version)}-arm64\.dmg/, "Monadic.Chat-#{to_version}-arm64.dmg")
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(from_version)}-x64\.dmg/, "Monadic.Chat-#{to_version}-x64.dmg")
    # Windows files
    updated_content = updated_content.gsub(/Monadic\.Chat\.Setup\.#{Regexp.escape(from_version)}\.exe/, "Monadic.Chat.Setup.#{to_version}.exe")
    # Linux files
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(from_version)}_amd64\.deb/, "monadic-chat_#{to_version}_amd64.deb")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(from_version)}_arm64\.deb/, "monadic-chat_#{to_version}_arm64.deb")
    # ZIP files for updates (all platforms)
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(from_version)}-arm64\.zip/, "Monadic.Chat-#{to_version}-arm64.zip")
    updated_content = updated_content.gsub(/Monadic\.Chat-#{Regexp.escape(from_version)}-x64\.zip/, "Monadic.Chat-#{to_version}-x64.zip")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(from_version)}_arm64\.zip/, "monadic-chat_#{to_version}_arm64.zip")
    updated_content = updated_content.gsub(/monadic-chat_#{Regexp.escape(from_version)}_x64\.zip/, "monadic-chat_#{to_version}_x64.zip")
    updated_content = updated_content.gsub(/Monadic\.Chat\.Setup\.#{Regexp.escape(from_version)}\.zip/, "Monadic.Chat.Setup.#{to_version}.zip")
  
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
        version_found = content.include?("/v#{official_version}/") &&
                        content.include?("Monadic.Chat-#{official_version}-arm64.dmg") &&
                        content.include?("Monadic.Chat-#{official_version}-x64.dmg") &&
                        content.include?("Monadic.Chat.Setup.#{official_version}.exe") &&
                        content.include?("monadic-chat_#{official_version}_amd64.deb")
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
          version_found = content.include?("/v#{from_version}/") &&
                          content.include?("Monadic.Chat-#{from_version}-arm64.dmg") &&
                          content.include?("Monadic.Chat-#{from_version}-x64.dmg") &&
                          content.include?("Monadic.Chat.Setup.#{from_version}.exe") &&
                          content.include?("monadic-chat_#{from_version}_amd64.deb")
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
  def setup_build_environment
    # remove /docker/services/python/pysetup.py
    FileUtils.rm_f("docker/services/python/pysetup.py")
    home_directory_path = File.join(File.dirname(__FILE__), "docker")
    Dir.glob("#{home_directory_path}/data/*").each { |file| FileUtils.rm_f(file) }
    Dir.glob("#{home_directory_path}/dist/*").each { |file| FileUtils.rm_f(file) }

    # Download vendor assets for offline use
    puts "Downloading vendor assets for offline use..."
    Rake::Task["download_vendor_assets"].invoke

    sh "npm update"
    sh "npm cache clean --force"
  end

  desc "Build Windows x64 package only"
  task :win do
    setup_build_environment
    puts "Building Windows x64 package..."
    sh "npm run build:win -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build macOS arm64 (Apple Silicon) package only"
  task :mac_arm64 do
    setup_build_environment
    puts "Building macOS arm64 package..."
    sh "npm run build:mac-arm64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build macOS x64 (Intel) package only"
  task :mac_x64 do
    setup_build_environment
    puts "Building macOS x64 package..."
    sh "npm run build:mac-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build Linux x64 package only"
  task :linux_x64 do
    setup_build_environment
    puts "Building Linux x64 package..."
    sh "npm run build:linux-x64 -- --publish never -c.generateUpdatesFilesForAllChannels=true"
  end

  desc "Build Linux arm64 package only"
  task :linux_arm64 do
    setup_build_environment
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
  # remove /docker/services/python/pysetup.py
  FileUtils.rm_f("docker/services/python/pysetup.py")
  home_directory_path = File.join(File.dirname(__FILE__), "docker")
  Dir.glob("#{home_directory_path}/data/*").each { |file| FileUtils.rm_f(file) }
  Dir.glob("#{home_directory_path}/dist/*").each { |file| FileUtils.rm_f(file) }

  # Download vendor assets for offline use
  puts "Downloading vendor assets for offline use..."
  Rake::Task["download_vendor_assets"].invoke

  sh "npm update"

  sh "npm cache clean --force"

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
  
  # Match the actual generated macOS file patterns but don't add them separately
  mac_files = Dir.glob("dist/Monadic.Chat-#{version}*")
  
  # Debug output to show what macOS files were found
  puts "Found macOS files:"
  mac_files.each { |f| puts "  #{File.basename(f)}" }
  
  # All needed files will be added to this list
  necessary_files = [
    # Use the same required patterns as release_assets for consistency
    # Windows files
    "Monadic.Chat.Setup.#{version}.exe",     # Windows installer
    "Monadic.Chat.Setup.#{version}.zip",     # Windows ZIP (for updates)
    
    # macOS files
    "Monadic.Chat-#{version}-arm64.dmg",     # macOS arm64 DMG
    "Monadic.Chat-#{version}-x64.dmg",       # macOS x64 DMG
    "Monadic.Chat-#{version}-arm64.zip",     # macOS arm64 ZIP (for updates)
    "Monadic.Chat-#{version}-x64.zip",       # macOS x64 ZIP (for updates)
    
    # Linux files
    "monadic-chat_#{version}_amd64.deb",     # Linux x64 DEB (uses Debian naming)
    "monadic-chat_#{version}_arm64.deb",     # Linux ARM64 DEB
    "monadic-chat_#{version}_x64.zip",       # Linux x64 ZIP (uses Node.js naming)
    "monadic-chat_#{version}_arm64.zip",     # Linux ARM64 ZIP (for updates)
    
    # Update YML files
    "latest.yml",                            # Windows update file
    "latest-mac.yml",                        # macOS x64 update file
    "latest-mac-arm64.yml",                  # macOS arm64 update file
    "latest-linux.yml",                      # Linux x64 update file
    "latest-linux-arm64.yml"                 # Linux arm64 update file
  ].map { |file| File.expand_path("dist/#{file}") }
  
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
  sh "rspec ./docker/services/ruby/spec --format documentation --no-fail-fast --no-profile"
end

# Test JavaScript code with Jest
desc "Run JavaScript tests using Jest"
task :jstest do
  sh "npm test"
end

# For backward compatibility
desc "Run all JavaScript tests using Jest"
task :jstest_all => :jstest

# Run both Ruby and JavaScript tests
desc "Run all tests (Ruby and JavaScript)"
task :test => [:spec, :jstest]

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
    required_patterns = [
      "dist/Monadic.Chat-#{version}-arm64.dmg",
      "dist/Monadic.Chat-#{version}-x64.dmg",
      "dist/Monadic.Chat-#{version}-arm64.zip",
      "dist/Monadic.Chat-#{version}-x64.zip",
      "dist/Monadic.Chat.Setup.#{version}.exe",
      "dist/Monadic.Chat.Setup.#{version}.zip",
      "dist/monadic-chat_#{version}_amd64.deb",
      "dist/monadic-chat_#{version}_arm64.deb",
      "dist/monadic-chat_#{version}_x64.zip",
      "dist/monadic-chat_#{version}_arm64.zip"
    ]
    
    missing_files = required_patterns.select { |pattern| Dir.glob(pattern).empty? }
    
    if !missing_files.empty?
      puts "Missing required files for version #{version}:"
      missing_files.each { |f| puts "  - #{f}" }
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
    
    # Use the same required patterns as build check for consistency
    required_patterns = [
      "Monadic.Chat-#{version}-arm64.dmg",      # macOS arm64
      "Monadic.Chat-#{version}-x64.dmg",        # macOS x64
      "Monadic.Chat-#{version}-arm64.zip",      # macOS arm64 ZIP (for updates)
      "Monadic.Chat-#{version}-x64.zip",        # macOS x64 ZIP (for updates)
      "Monadic.Chat.Setup.#{version}.exe",      # Windows
      "Monadic.Chat.Setup.#{version}.zip",      # Windows ZIP (for updates)
      "monadic-chat_#{version}_amd64.deb",      # Linux x64 (uses Debian naming)
      "monadic-chat_#{version}_arm64.deb",      # Linux ARM64
      "monadic-chat_#{version}_x64.zip",        # Linux x64 ZIP (uses Node.js naming)
      "monadic-chat_#{version}_arm64.zip"       # Linux ARM64 ZIP (for updates)
    ].each do |file|
      path = File.join("dist", file)
      if File.exist?(path)
        release_assets << path
      else
        puts "Warning: Release asset not found: #{path}"
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
    if file_patterns.nil?
      # Default patterns if none provided
      patterns = [
        "dist/Monadic.Chat-#{version}-arm64.dmg",
        "dist/Monadic.Chat-#{version}-x64.dmg",
        "dist/Monadic.Chat-#{version}-arm64.zip",
        "dist/Monadic.Chat-#{version}-x64.zip",
        "dist/Monadic.Chat.Setup.#{version}.exe",
        "dist/Monadic.Chat.Setup.#{version}.zip",
        "dist/monadic-chat_#{version}_amd64.deb",
        "dist/monadic-chat_#{version}_arm64.deb",
        "dist/monadic-chat_#{version}_x64.zip",
        "dist/monadic-chat_#{version}_arm64.zip",
        "dist/*.yml"  # Include all YML files for auto-updates
      ]
    else
      patterns = file_patterns.split(/\s+/)
    end
    
    # Expand file patterns
    files_to_update = []
    patterns.each do |pattern|
      expanded_files = Dir.glob(pattern)
      if expanded_files.empty?
        puts "Warning: No files found matching pattern '#{pattern}'"
      else
        files_to_update.concat(expanded_files)
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
