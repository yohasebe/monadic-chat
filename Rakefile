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
    "./docs/_coverpage.md"
  ]
  
  # Dynamically find all installation.md files in the docs directories
  installation_files = Dir.glob("./docs/**/installation.md").uniq
  
  # Combine the static files with the dynamically found installation files
  static_files + installation_files
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
    # For installation.md files, carefully update only version numbers in download URLs and version indicators
    updated_content = content.dup
    
    # Fix macOS ARM64 URL
    updated_content = updated_content.gsub(/(Monadic%20Chat-)#{Regexp.escape(from_version)}(-arm64\.dmg)/, "\\1#{to_version}\\2")
    
    # Fix macOS x64 URL
    updated_content = updated_content.gsub(/(Monadic%20Chat-)#{Regexp.escape(from_version)}(\.dmg)/, "\\1#{to_version}\\2")
    
    # Fix Windows URL
    updated_content = updated_content.gsub(/(Monadic%20Chat%20Setup%20)#{Regexp.escape(from_version)}(\.exe)/, "\\1#{to_version}\\2")
    
    # Fix Linux amd64 URL
    updated_content = updated_content.gsub(/(monadic-chat_)#{Regexp.escape(from_version)}(_amd64\.deb)/, "\\1#{to_version}\\2")
    
    # Fix Linux arm64 URL
    updated_content = updated_content.gsub(/(monadic-chat_)#{Regexp.escape(from_version)}(_arm64\.deb)/, "\\1#{to_version}\\2")
    
    # Update version indicators in parentheses (the version shown next to download links)
    updated_content = updated_content.gsub(/\(#{Regexp.escape(from_version)}\)/, "(#{to_version})")
  
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
        # Check for version in URLs and parentheses
        version_found = content.include?("Monadic%20Chat-#{official_version}") || 
                        content.include?("Monadic%20Chat%20Setup%20#{official_version}") ||
                        content.include?("monadic-chat_#{official_version}_") ||
                        content =~ /\(#{Regexp.escape(official_version)}\)/
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

desc "Update version number in all relevant files. Usage: rake update_version[0.9.63,0.9.64] - Updates all version references and adds a changelog entry"
task :update_version, [:from_version, :to_version] do |_t, args|
  require 'date'
  
  from_version = args[:from_version]
  to_version = args[:to_version]
  
  # Check if this is a dry run
  dry_run = ENV['DRYRUN'] == 'true'
  dry_run_message = dry_run ? " (DRY RUN - no files will be modified)" : ""
  
  if from_version.nil? || to_version.nil?
    puts "Usage: rake update_version[from_version,to_version] [DRYRUN=true]"
    puts "Example: rake update_version[0.9.63,0.9.64]"
    puts "Example (dry run): rake update_version[0.9.63,0.9.64] DRYRUN=true"
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
          version_found = content.include?("Monadic%20Chat-#{from_version}") || 
                          content.include?("Monadic%20Chat%20Setup%20#{from_version}") ||
                          content.include?("monadic-chat_#{from_version}_") ||
                          content.include?("(#{from_version})")
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

# task to build win/mac x64/mac arm64 packages
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

  sh "npm run build:linux-x64"
  sh "npm run build:linux-arm64"
  sh "npm run build:win"
  sh "npm run build:mac-x64"
  sh "npm run build:mac-arm64"

  necessary_files = [
    "Monadic Chat-#{version}-arm64.dmg",
    "Monadic Chat-#{version}.dmg",
    "Monadic Chat Setup #{version}.exe",
    "monadic-chat_#{version}_amd64.deb",
    "monadic-chat_#{version}_arm64.deb"
  ].map { |file| File.expand_path("dist/#{file}") }

  Dir.glob("dist/*").each do |file|
    filepath = File.expand_path(file)
    FileUtils.rm_rf(filepath) unless necessary_files.include?(filepath)
    # move the file to the /docs/assets/download/ directory if it is included in necessary_files
    # FileUtils.mv(filepath, "docs/assets/download/") if necessary_files.include?(filepath)
  end
end

# Test ruby code with rspec ./docker/services/ruby/spec
task :spec do
  sh "rspec ./docker/services/ruby/spec"
end
