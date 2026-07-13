# frozen_string_literal: true

# GitHub Release Management Tasks
namespace :release do
  desc "Build, package, and create a new GitHub release"
  task :github, [:version, :prerelease, :target] do |_t, args|
    version = args[:version] || get_current_version
    prerelease = args[:prerelease] == 'true'
    # Optional commit-ish (SHA/branch/tag) the release tag is created at. When
    # omitted, `gh release create` places the tag at the remote default
    # branch's HEAD — which can point at the WRONG tree if the built artifacts
    # came from a different commit. Pass the exact release commit to be safe.
    target = args[:target]

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
    
    # Check for and include YML files for auto-updates. Exclude
    # builder-debug.yml — it is electron-builder's debug dump, not an
    # auto-update manifest, and must not be attached (the release ships the 5
    # latest-*.yml manifests only).
    puts "Searching for auto-update YML files in dist directory..."
    update_ymls = Dir.glob("dist/*.yml").reject { |f| File.basename(f) == "builder-debug.yml" }
    update_ymls.each do |yml_path|
      yml_file = File.basename(yml_path)
      release_assets << yml_path
      puts "Found YML asset for auto-update: #{yml_path}"
    end

    if update_ymls.empty?
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
      
      # Pin the tag to the intended release commit when a target is given, so
      # the tag never lands on a stale default-branch HEAD.
      target_arg = target && !target.to_s.strip.empty? ? "--target #{target}" : ""

      # Create the release command
      release_cmd = "gh release create v#{version} #{escaped_assets} --title 'Monadic Chat #{version}' --notes-file #{release_notes_file} #{prerelease_arg} #{target_arg}".squeeze(" ").strip

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
      
      # Also include all auto-update YML files (excluding the debug dump)
      files_to_update.concat(Dir.glob("dist/*.yml").reject { |f| File.basename(f) == "builder-debug.yml" })
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
