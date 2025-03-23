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
  [
    "./docker/services/ruby/lib/monadic/version.rb",
    "./package.json",
    "./package-lock.json",
    "./docker/monadic.sh",
    "./docs/_coverpage.md",
    "./docs/installation.md",
    "./docs/ja/installation.md"
  ]
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
      if content.include?(official_version)
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
  
  if from_version.nil? || to_version.nil?
    puts "Usage: rake update_version[from_version,to_version]"
    puts "Example: rake update_version[0.9.63,0.9.64]"
    exit 1
  end
  
  # Current month and year for changelog
  current_date = Date.today
  month_year = "#{current_date.strftime('%B')}, #{current_date.year}"
  
  # Files to update with exact replacements
  files = version_files
  
  from_version_regex = Regexp.escape(from_version)
  
  # Update each file
  files.each do |file|
    if File.exist?(file)
      content = File.read(file)
      if content.include?(from_version)
        puts "Updating version in #{file} from #{from_version} to #{to_version}"
        updated_content = content.gsub(/#{from_version_regex}/, to_version)
        File.write(file, updated_content)
      else
        puts "Version #{from_version} not found in #{file}"
      end
    else
      puts "File not found: #{file}"
    end
  end
  
  # Add an entry to CHANGELOG.md if it doesn't already exist
  changelog = "./CHANGELOG.md"
  if File.exist?(changelog)
    content = File.read(changelog)
    unless content.include?("- [#{month_year}] #{to_version}")
      lines = content.lines
      
      # Check if first line contains the current month and from_version
      first_line = lines[0].strip
      if first_line.include?("[#{month_year}]") && first_line.include?(from_version)
        # Update the version number in the current month's entry
        lines[0] = first_line.gsub(from_version, to_version) + "\n"
        puts "Updating current month entry in CHANGELOG.md from #{from_version} to #{to_version}"
      else
        # Create a new entry for the current month
        new_entry = "- [#{month_year}] #{to_version}\n  - Version updated from #{from_version}\n\n"
        lines.unshift(new_entry)
        puts "Adding new entry to CHANGELOG.md for version #{to_version}"
      end
      File.write(changelog, lines.join)
    end
  end
  
  puts "Version update completed!"
  
  # Run check_version to verify the update
  puts "\nVerifying version consistency after update:"
  Rake::Task["check_version"].invoke
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
