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
  
  # Note: installation.md files are not included here because they're
  # updated separately in the release:github task with specific version numbers
  
  # Return only the static files
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
    # IMPORTANT: Do not update installation.md here
    # Installation docs are updated separately in the release:github task
    # to ensure docs are only updated when actual releases are made
    puts "Skipping installation.md update - this should be done only in release:github task"
    return false
  
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
        # IMPORTANT: Skip checking installation.md files for version consistency
        # These are updated separately during release:github task
        puts "Skipping version check for installation.md - this file is managed by release:github task"
        version_found = true # Skip checking
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
          # IMPORTANT: Skip checking installation.md files - they're updated separately during actual releases
          puts "Skipping version check for installation.md in dry run"
          version_found = true # Skip checking
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

  sh "npm run build:linux-x64"
  sh "npm run build:linux-arm64"
  sh "npm run build:win"
  sh "npm run build:mac-x64"
  sh "npm run build:mac-arm64"

  necessary_files = [
    "Monadic Chat-#{version}-arm64.dmg",  # macOS arm64
    "Monadic Chat-#{version}.dmg",        # macOS x64
    "Monadic Chat Setup #{version}.exe",  # Windows
    "monadic-chat_#{version}_amd64.deb",  # Linux x64
    "monadic-chat_#{version}_arm64.deb"   # Linux arm64
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
    
    # Step 2: Build all packages if needed
    if Dir.glob("dist/Monadic Chat*#{version}*").empty?
      puts "Building packages for version #{version}..."
      Rake::Task["build"].invoke
    else
      puts "Found existing packages for version #{version}"
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
    
    ["Monadic Chat-#{version}-arm64.dmg",  # macOS arm64
     "Monadic Chat-#{version}.dmg",        # macOS x64
     "Monadic Chat Setup #{version}.exe",  # Windows
     "monadic-chat_#{version}_amd64.deb",  # Linux x64
     "monadic-chat_#{version}_arm64.deb"].each do |file|
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
    
    # No longer creating "latest" versions of assets - will update documentation instead
    puts "Total assets for release: #{release_assets.length}"
    
    # Update installation documentation with the current version number
    ["./docs/getting-started/installation.md", "./docs/ja/getting-started/installation.md"].each do |install_doc|
      if File.exist?(install_doc)
        content = File.read(install_doc)
        updated_content = content.dup
        
        # Update macOS ARM64 URL
        updated_content = updated_content.gsub(/\/Monadic%20Chat-[^\/]+-arm64\.dmg/, "/Monadic%20Chat-#{version}-arm64.dmg")
        
        # Update macOS x64 URL
        updated_content = updated_content.gsub(/\/Monadic%20Chat-[^-][^\/]*\.dmg/, "/Monadic%20Chat-#{version}.dmg")
        
        # Update Windows URL
        updated_content = updated_content.gsub(/\/Monadic%20Chat%20Setup%20[^\/]*\.exe/, "/Monadic%20Chat%20Setup%20#{version}.exe")
        
        # Update Linux x64 URL
        updated_content = updated_content.gsub(/\/monadic-chat_[^\/]*_amd64\.deb/, "/monadic-chat_#{version}_amd64.deb")
        
        # Update Linux arm64 URL
        updated_content = updated_content.gsub(/\/monadic-chat_[^\/]*_arm64\.deb/, "/monadic-chat_#{version}_arm64.deb")
        
        # Update version notes in documentation
        if install_doc.include?('/ja/')
          # Japanese documentation - more flexible pattern matching
          if updated_content =~ /\*(?:バージョン [^。]+。)?(?:\[GitHub|\[GitHubリリースページ).*?(?:すべての利用可能なバージョン|他のバージョン).*?\*/
            updated_content = updated_content.gsub(/\*(?:バージョン [^。]+。)?(?:\[GitHub|\[GitHubリリースページ).*?(?:すべての利用可能なバージョン|他のバージョン).*?\*/, 
              "*バージョン #{version}。[GitHubリリースページ](https://github.com/yohasebe/monadic-chat/releases/latest)で、他のバージョンも確認できます。*")
          else
            # If no version text is found, log warning
            puts "Warning: Could not find version text pattern in Japanese documentation"
          end
        else
          # English documentation - more flexible pattern matching
          if updated_content =~ /\*(?:Version [^.]+\.)?(?:\[GitHub|\[GitHub Releases).*?(?:all available versions|other versions).*?\*/
            updated_content = updated_content.gsub(/\*(?:Version [^.]+\.)?(?:\[GitHub|\[GitHub Releases).*?(?:all available versions|other versions).*?\*/, 
              "*Version #{version}. You can also visit the [GitHub Releases page](https://github.com/yohasebe/monadic-chat/releases/latest) to see other versions.*")
          else
            # If no version text is found, log warning
            puts "Warning: Could not find version text pattern in English documentation"
          end
        end
        
        # Check if content actually changed
        if updated_content != content
          puts "Updating download links in #{install_doc} to version #{version}"
          File.write(install_doc, updated_content)
          
          # Verify that the changes were applied correctly
          verification_content = File.read(install_doc)
          
          # Check for specific version in the updated file
          if verification_content.include?(version)
            puts "✓ Successfully updated version references in #{install_doc}"
          else
            puts "⚠ Warning: Updated file doesn't contain version #{version}. Changes may not have been applied correctly."
          end
        else
          # Check if file already contains the current version
          if content.include?(version)
            puts "No updates needed for #{install_doc} (already contains version #{version})"
          else
            puts "⚠ Warning: No changes were made to #{install_doc}, but it doesn't contain version #{version}"
            puts "   This might indicate that URL patterns were not matched correctly."
          end
        end
      else
        puts "Warning: Installation documentation file not found: #{install_doc}"
      end
    end
    
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
  
  desc "Delete a GitHub release and its assets"
  task :delete, [:version] do |_t, args|
    version = args[:version]
    
    if version.nil?
      puts "Error: Version required. Use rake release:delete[version]"
      exit 1
    end
    
    # Confirm deletion
    print "Are you sure you want to delete release v#{version}? This cannot be undone! (y/N): "
    response = STDIN.gets.chomp.downcase
    exit 1 unless response == 'y'
    
    # Delete the release
    puts "Deleting GitHub release v#{version}..."
    sh "gh release delete v#{version}"
    puts "Release deleted successfully!"
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
