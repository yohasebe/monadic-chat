# frozen_string_literal: true

require 'open3'

# Establishes which commit CI actually ran against, and refuses to go on unless
# it passed.
#
# The release commit on `main` is created with `commit-tree` from dev's tree, so
# it has no CI of its own at this point. The tree is what carries over, so the
# gate asks the remote for dev's tip, requires its tree to be the one being
# released, and then checks that commit. Asking the local `origin/dev` instead
# would read a tracking ref that may be behind, which would verify an older
# tree's green and report it as this release's.
#
# Deliberately has no override: an environment variable that disables a release
# gate is a gate that stops being one.
def verify_release_ci_green(target)
  if target.to_s.empty?
    abort "Error: pass the release commit as the third argument, e.g.\n" \
          "  rake \"release:github[<version>,true,$NEW]\"\n" \
          'Without it there is no commit to check CI against, and the tag would ' \
          "be placed at the remote default branch's HEAD."
  end

  remote, status = Open3.capture2('git', 'ls-remote', 'origin', 'refs/heads/dev')
  abort 'Error: cannot read origin/dev; CI results cannot be checked.' unless status.success?

  dev_sha = remote.split(/\s+/).first.to_s
  abort 'Error: origin has no dev branch; CI results cannot be checked.' unless dev_sha.match?(/\A[0-9a-f]{40}\z/)

  dev_tree = git_tree_of(dev_sha)
  if dev_tree.nil?
    abort "Error: #{dev_sha[0, 8]} is not in this clone. Run `git fetch origin dev` and try again."
  end

  # Pin the release to a commit now, and use that SHA everywhere afterwards.
  # `main` or a tag resolves here, but `gh release create --target main` is
  # resolved by GitHub when the release is made -- minutes later, after the
  # build -- so the commit checked and the commit published could differ.
  release_sha = git_commit_of(target)
  abort "Error: #{target} cannot be resolved to a commit." if release_sha.nil?

  target_tree = git_tree_of(release_sha)
  abort "Error: #{target} cannot be resolved to a commit." if target_tree.nil?

  unless dev_tree == target_tree
    abort "Error: the release commit's tree is not the tree CI ran against.\n" \
          "  release commit #{release_sha[0, 8]}: tree #{target_tree[0, 8]}\n" \
          "  origin/dev #{dev_sha[0, 8]}: tree #{dev_tree[0, 8]}\n" \
          'Push the release candidate to dev first, or rebuild the release ' \
          'commit from the dev tip that CI checked.'
  end

  puts "Checking CI for #{dev_sha[0, 8]} (dev), whose tree is what this release publishes..."
  unless system('ruby', 'scripts/verify_ci_green.rb', dev_sha, 'dev')
    abort 'Error: nothing was published. Fix CI on dev and release the commit that passed.'
  end

  [dev_sha, release_sha]
end

# Run again immediately before publishing, on the commit the first check
# settled on rather than whatever dev points at now.
#
# Building four platforms takes long enough for someone to re-run CI on that
# commit, and the release tag is pushed before this task runs, so `--target`
# does not move an existing tag: `gh release create` attaches the release to
# the tag that is already there. A tag left over at an older commit would
# publish a tree nobody checked, with the gate reporting success for a
# different one.
def verify_release_is_still_publishable(version, target, dev_sha)
  tag = "v#{version}"
  # Both refs are named: asking only for refs/tags/<tag> returns the tag
  # OBJECT for an annotated tag and no peeled line at all, so the commit it
  # points at never appears and a correct release would be refused.
  remote, status = Open3.capture2('git', 'ls-remote', 'origin',
                                  "refs/tags/#{tag}", "refs/tags/#{tag}^{}")
  abort "Error: cannot read the #{tag} tag on origin; nothing was published." unless status.success?

  entries = remote.lines.filter_map do |line|
    sha, ref = line.split(/\s+/)
    [sha, ref] if sha && ref
  end
  peeled = entries.find { |_sha, ref| ref == "refs/tags/#{tag}^{}" }
  plain = entries.find { |_sha, ref| ref == "refs/tags/#{tag}" }
  tagged = (peeled || plain)&.first

  if tagged && tagged != target
    abort "Error: #{tag} on origin points at #{tagged[0, 8]}, not the release commit " \
          "#{target[0, 8]} that was checked.\n" \
          "  `gh release create` attaches to the existing tag, so the release would " \
          "publish a commit this gate never looked at.\n" \
          "  Delete or move the tag, then release again."
  end

  puts "Re-checking CI for #{dev_sha[0, 8]} before publishing..."
  unless system('ruby', 'scripts/verify_ci_green.rb', dev_sha, 'dev')
    abort 'Error: CI is no longer green for this commit; nothing was published.'
  end
end

# Resolves to the commit a ref points at, so the rest of the release works
# with one fixed SHA instead of a name that can move under it.
def git_commit_of(commitish)
  out, status = Open3.capture2e('git', 'rev-parse', '--verify', '--quiet', "#{commitish}^{commit}")
  sha = out.strip
  status.success? && sha.match?(/\A[0-9a-f]{40}\z/) ? sha : nil
end

def git_tree_of(commitish)
  out, status = Open3.capture2e('git', 'rev-parse', '--verify', '--quiet', "#{commitish}^{tree}")
  status.success? ? out.strip : nil
end

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

    # Step 0: Refuse to publish a tree whose CI did not pass. beta.35 went out
    # with Lint red because every other gate here looks at the artifacts. The
    # workflows ran against the dev commit, and the release commit is built
    # from that same tree by commit-tree, so the tree is what ties the two
    # together — see verify_release_ci_green.
    #
    # `target` becomes the resolved commit SHA: everything after this point --
    # the tag comparison and `--target` -- must name the commit that was
    # checked, not a branch GitHub would resolve again at publish time.
    verified_dev_sha, target = verify_release_ci_green(target)

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
    
    # Attach the auto-update manifests by name rather than by glob, and stop
    # if the set is not exactly the one the patch/verify scripts cover. See
    # scripts/release_manifest_set.rb for why the glob was not safe.
    require_relative "../scripts/release_manifest_set"

    puts "Collecting auto-update YML files from dist directory..."
    update_ymls, manifest_error = ReleaseManifestSet.select("dist")
    if manifest_error
      puts "Error: #{manifest_error}"
      exit 1
    end
    update_ymls.each { |yml_path| puts "Found YML asset for auto-update: #{yml_path}" }
    release_assets.concat(update_ymls)

    # Verify the files that are about to be published, not a previous run's
    # dist. When every package already exists the build step above is skipped,
    # so without this the task would happily attach manifests whose hashes
    # drifted or whose macOS floor was lost.
    puts "Verifying the manifests against the artifacts being published..."
    unless system("ruby", "scripts/verify_release_manifests.rb")
      puts "Error: manifest verification failed; nothing was published."
      exit 1
    end

    # And that the archives carry only the payload that was staged. Releases
    # beta.21 through beta.32 shipped git-ignored files this catches.
    puts "Verifying the packaged payload against the staged allow list..."
    unless system("ruby", "scripts/verify_bundle_payload.rb")
      puts "Error: packaged payload verification failed; nothing was published."
      exit 1
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
      
      # Last gate before the release exists: the tag the assets will hang
      # off, and the CI of the commit they came from, are both re-checked
      # here because the build between the two checks takes minutes.
      verify_release_is_still_publishable(version, target, verified_dev_sha)

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
  task :draft, [:version, :prerelease, :target] do |_t, args|
    # Set the DRAFT environment variable to true
    ENV['DRAFT'] = 'true'

    # Takes the release commit for the same reason release:github does: a
    # draft still creates the tag and carries the assets, so it has to name
    # the commit whose CI was checked.
    Rake::Task["release:github"].invoke(args[:version], args[:prerelease], args[:target])
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
      
      # Auto-update manifests go through the same selection as release:github:
      # uploading one that nothing patched or verified is the same hazard here,
      # and this task replaces assets on an already-published release.
      require_relative "../scripts/release_manifest_set"
      manifests, manifest_error = ReleaseManifestSet.select("dist")
      if manifest_error
        puts "Error: #{manifest_error}"
        exit 1
      end
      files_to_update.concat(manifests)
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
