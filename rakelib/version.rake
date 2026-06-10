# frozen_string_literal: true

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
