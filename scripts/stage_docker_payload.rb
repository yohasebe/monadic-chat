#!/usr/bin/env ruby
# frozen_string_literal: true

# Assembles the `docker/` payload that ships inside the desktop app.
#
# electron-builder used to copy `./docker` wholesale, excluding only dotfiles.
# That is a deny list: it ships whatever happens to be sitting in the working
# tree, so files that were git-ignored but present — benchmark logs, __pycache__,
# rspec run state, test audio — went into every published release from
# beta.21 onward, carrying this machine's absolute paths with them.
#
# The rule here is the inverse: a file ships because it was named, not because
# nothing excluded it. Two sources are allowed.
#
#   1. Everything git tracks under `docker/`. Tracked means reviewed, and a new
#      private file is untracked by default, so it cannot reach a release by
#      being forgotten.
#   2. Build products named individually below. These are generated, so they are
#      never tracked, but the app cannot run without them. Each is required: a
#      missing one fails the build rather than shipping an app whose UI has no
#      stylesheet or whose help database is empty.
#
# `bin/` ships the same way and for the same reason: it happens to be clean
# today, but it was carrying the identical deny-list filter.
#
# Writes the payload to build/app-payload/{docker,bin} and the list of what it
# contains to build/app-payload.manifest, which verify_bundle_payload.rb
# compares the packaged archives against.

require 'fileutils'
require 'json'
require 'pathname'
require 'set'
require_relative 'help_dump_guard'

ROOT = Pathname.new(File.expand_path('..', __dir__))
OUT = ROOT.join('build/app-payload')
MANIFEST = ROOT.join('build/app-payload.manifest')
SYMLINKS = ROOT.join('build/app-payload.symlinks')

# The app itself (app.asar) is packed by electron-builder from app/, icons/,
# package.json and the production dependencies. These two lists record what it
# may contain, so verify_bundle_payload.rb can compare the packed asar against
# them the way it compares docker/ against MANIFEST.
ASAR_MANIFEST = ROOT.join('build/app-asar.manifest')
ASAR_MODULES = ROOT.join('build/app-asar.modules')
ASAR_TREES = %w[app icons package.json].freeze

def asar_tracked_paths
  out = `git -C "#{ROOT}" ls-files -z -- #{ASAR_TREES.join(' ')}`
  raise 'git ls-files failed' unless $?.success?

  out.split("\0").reject(&:empty?).sort
end

# Packages npm installs for production, as name@version. electron-builder
# re-arranges node_modules when it packs the asar (it hoists nested copies),
# so the packed paths differ from npm's; the packages themselves do not.
def production_modules
  out = `cd "#{ROOT}" && npm ls --omit=dev --all --json 2>/dev/null`
  tree = JSON.parse(out) rescue {}
  mods = []
  walk = lambda do |deps|
    (deps || {}).each do |name, info|
      mods << "#{name}@#{info['version']}" if info['version']
      walk.call(info['dependencies'])
    end
  end
  walk.call(tree['dependencies'])
  mods = mods.uniq.sort
  abort '[stage_docker_payload] npm ls listed no production modules' if mods.empty?
  mods
end

# Tracked files ship as they are committed, not as they sit in the working
# tree. A path list cannot tell the two apart: a debug line added to a
# tracked file passes every path comparison. Staging refuses shipped files
# with uncommitted changes, and records each one's blob ID at HEAD so
# verify_bundle_payload.rb can compare the packed bytes with the commit.
BLOBS = ROOT.join('build/app-tracked.blobs')
ALLOW_UNCOMMITTED = 'MONADIC_ALLOW_UNCOMMITTED_BUILD'

def uncommitted_paths(shipped)
  out = `git -C "#{ROOT}" status --porcelain=v1 -z --untracked-files=no -- #{(SHIPPED_TREES + ASAR_TREES).join(' ')}`
  raise 'git status failed' unless $?.success?

  # Each record is "XY path"; a rename adds the old path as its own record.
  changed = out.split("\0").reject(&:empty?).map { |r| r.length > 3 && r[2] == ' ' ? r[3..] : r }
  (changed & shipped).sort
end

# "blob<TAB>path" for every shipped tracked file at HEAD. Symlinks are left
# out: their blob is the link text, which staging already compares, and
# Windows stores the target's contents in their place.
def head_blobs(shipped)
  out = `git -C "#{ROOT}" ls-tree -r -z HEAD -- #{(SHIPPED_TREES + ASAR_TREES).join(' ')}`
  raise 'git ls-tree failed' unless $?.success?

  wanted = shipped.to_set
  out.split("\0").reject(&:empty?).filter_map do |rec|
    meta, path = rec.split("\t", 2)
    mode, _type, sha = meta.split(' ')
    "#{sha}\t#{path}" if wanted.include?(path) && mode != '120000'
  end.sort
end

# Generated at build time, required at run time. Globs are relative to ROOT.
REQUIRED_BUILD_PRODUCTS = [
  'docker/services/ruby/public/vendor/**/*',
  'docker/services/ruby/public/js/monadic.bundle.min.js',
  'docker/services/ruby/help_data/help_db.json'
].freeze

# The directories that ship inside the app, each mirrored under OUT by name.
SHIPPED_TREES = %w[docker bin].freeze

# Tracked, but only so that git keeps an otherwise-empty directory. They mean
# nothing once the app is packaged, and electron-builder drops them by name
# anyway (app-builder-lib's fileMatcher excludes .gitkeep alongside .DS_Store
# and __pycache__), so staging them would guarantee a mismatch between what
# was staged and what shipped.
GIT_BOOKKEEPING = %w[.gitkeep .gitignore .gitattributes].freeze

# Tracked, shipped, and read by nothing. The packaged `docker/` tree exists to
# be the build context for the Ruby image, and that image's .dockerignore
# already excludes these, so they reach neither the container nor any runtime
# path — they only make the download larger and make a test edit change the
# shipped bytes. Kept in step with .dockerignore by a check below.
EXCLUDED_FROM_PAYLOAD = [
  %r{\Adocker/services/ruby/spec/},
  %r{\Adocker/services/ruby/docs/}
].freeze

def tracked_paths
  out = `git -C "#{ROOT}" ls-files -z #{SHIPPED_TREES.join(' ')}`
  raise 'git ls-files failed' unless $?.success?

  out.split("\0").reject(&:empty?)
     .reject { |p| GIT_BOOKKEEPING.include?(File.basename(p)) }
     .reject { |p| EXCLUDED_FROM_PAYLOAD.any? { |re| p.match?(re) } }
end

# The exclusions above are only safe while the Ruby image also leaves these
# out. If .dockerignore stopped excluding them the container build would need
# them from the payload, and dropping them here would break it silently.
def assert_dockerignore_agrees
  ignore = ROOT.join('docker/services/ruby/.dockerignore')
  return unless ignore.file?

  entries = ignore.read.split("\n").map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  %w[spec/ docs/].each do |dir|
    next if entries.include?(dir)

    abort "[stage_docker_payload] .dockerignore no longer excludes #{dir}, but the payload does.\n" \
          '  Bring the two back in step before building.'
  end
end
assert_dockerignore_agrees

# What may and may not ship in the help dump is decided in HelpDumpGuard,
# so the packaging entry points and the lint self-test share one answer.
def assert_help_dump_is_public
  problems = HelpDumpGuard.problems(
    dump_path: ROOT.join('docker/services/ruby/help_data/help_db.json'),
    root: ROOT
  )
  return if problems.empty?

  abort "[stage_docker_payload] refusing to package the help dump:\n  " +
        problems.join("\n  ") +
        "\n  Regenerate it with `rake help:build` (public documentation only).\n" \
        '  `rake help:build_internal` produces a developer dump that must not ship.'
end
assert_help_dump_is_public

def build_product_paths
  REQUIRED_BUILD_PRODUCTS.flat_map do |pattern|
    # Symlinks count: `public/vendor/css/fonts` points at the sibling font
    # directory, and the stylesheets resolve through it. Dropping it would
    # ship a UI with no fonts.
    matches = Dir.glob(ROOT.join(pattern).to_s).select { |p| File.file?(p) || File.symlink?(p) }
    if matches.empty?
      abort "[stage_docker_payload] required build product missing: #{pattern}\n" \
            '  Run the build steps that generate it (vendor fetch, JS bundle, help database).'
    end
    matches.map { |p| Pathname.new(p).relative_path_from(ROOT).to_s }
  end
end

paths = (tracked_paths + build_product_paths).uniq.sort
missing = paths.reject { |p| ROOT.join(p).file? || ROOT.join(p).symlink? }
unless missing.empty?
  abort "[stage_docker_payload] tracked but not on disk (#{missing.size}):\n  " + missing.first(10).join("\n  ")
end

# git status trusts the index, and a file marked --skip-worktree or
# --assume-unchanged never appears in it. So the files are also hashed and
# compared with HEAD, the way verify_bundle_payload.rb compares the archives.
def differs_from_head(shipped)
  blobs = head_blobs(shipped).to_h { |l| l.split("\t", 2).reverse }
  files = blobs.keys.select { |p| ROOT.join(p).file? && !ROOT.join(p).symlink? }
  return [] if files.empty?

  out = IO.popen(['git', '-C', ROOT.to_s, 'hash-object', '--no-filters', '--stdin-paths'], 'r+') do |io|
    io.write(files.join("\n") + "\n")
    io.close_write
    io.read
  end
  raise 'git hash-object failed' unless $?.success?

  files.zip(out.split("\n")).reject { |p, sha| blobs[p] == sha }.map(&:first)
end

shipped_tracked = (tracked_paths + asar_tracked_paths).uniq
dirty = (uncommitted_paths(shipped_tracked) + differs_from_head(shipped_tracked)).uniq.sort
unless dirty.empty?
  msg = "[stage_docker_payload] #{dirty.size} shipped file(s) have uncommitted changes:\n  " +
        dirty.first(15).join("\n  ")
  abort msg + "\n  Commit or stash them; a build ships what is committed." unless ENV[ALLOW_UNCOMMITTED] == '1'

  # For a local test build only: verify_bundle_payload.rb still compares the
  # packed files with HEAD, so a build made this way cannot be published.
  warn msg + "\n  Continuing because #{ALLOW_UNCOMMITTED}=1. This build cannot pass verify_bundle_payload.rb."
end

# `--check` stages nothing: it reports whether the payload already staged is
# the one staging would produce now. Packaging reads build/app-payload as it
# is, so a payload left over from an earlier build ships stale files — the
# same list with older contents, or files since deleted — unless something
# compares it against the current sources before electron-builder copies it.
def staged_problems(paths)
  problems = []
  recorded = MANIFEST.file? ? MANIFEST.read.split("\n").reject(&:empty?) : nil
  if recorded.nil?
    problems << "no manifest at #{MANIFEST.relative_path_from(ROOT)}"
  elsif recorded != paths
    (paths - recorded).first(10).each { |p| problems << "not staged: #{p}" }
    (recorded - paths).first(10).each { |p| problems << "staged but no longer shipped: #{p}" }
  end
  paths.each do |path|
    src = ROOT.join(path)
    dest = OUT.join(path)
    if src.symlink?
      same = dest.symlink? && File.readlink(dest) == File.readlink(src)
    else
      same = dest.file? && !dest.symlink? && FileUtils.compare_file(src, dest)
    end
    problems << "differs from its source: #{path}" unless same
    break if problems.size >= 20
  end
  on_disk = Dir.glob(OUT.join('**', '*').to_s, File::FNM_DOTMATCH)
               .select { |f| File.file?(f) || File.symlink?(f) }
               .map { |f| Pathname.new(f).relative_path_from(OUT).to_s }
  (on_disk - paths).first(10).each { |p| problems << "in the staging directory but not in the payload: #{p}" }
  { ASAR_MANIFEST => asar_tracked_paths, ASAR_MODULES => production_modules,
    BLOBS => head_blobs((tracked_paths + asar_tracked_paths).uniq) }.each do |file, now|
    recorded_list = file.file? ? file.read.split("\n").reject(&:empty?) : nil
    next if recorded_list == now

    problems << "#{file.relative_path_from(ROOT)} is #{recorded_list ? 'out of date' : 'missing'}"
  end
  problems
end

if ARGV.include?('--check')
  problems = staged_problems(paths)
  if problems.empty?
    puts "[stage_docker_payload] staged payload is current (#{paths.size} files)"
    exit 0
  end
  warn "[stage_docker_payload] the staged payload does not match the current sources:"
  problems.each { |pr| warn "  #{pr}" }
  warn '  Stage it again: ruby scripts/stage_docker_payload.rb'
  exit 1
end

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

paths.each do |path|
  src = ROOT.join(path)
  dest = OUT.join(path)
  FileUtils.mkdir_p(dest.dirname)

  if src.symlink?
    File.symlink(File.readlink(src), dest)
  else
    FileUtils.cp(src, dest, preserve: true)
    FileUtils.chmod(File.stat(src).mode & 0o7777, dest)
  end
end

FileUtils.mkdir_p(MANIFEST.dirname)
MANIFEST.write(paths.join("\n") + "\n")
ASAR_MANIFEST.write(asar_tracked_paths.join("\n") + "\n")
ASAR_MODULES.write(production_modules.join("\n") + "\n")
BLOBS.write(head_blobs(shipped_tracked).join("\n") + "\n")

# Recorded separately because Windows cannot store symlinks: electron-builder
# copies the target's contents in their place, so the packaged file list is
# legitimately different there. The verifier needs the link to tell that apart
# from a stray file.
links = paths.select { |p| ROOT.join(p).symlink? }
                 .map { |p| "#{p}\t#{File.readlink(ROOT.join(p))}" }
SYMLINKS.write(links.empty? ? '' : links.join("\n") + "\n")

tracked_count = tracked_paths.size
puts "[stage_docker_payload] staged #{paths.size} files " \
     "(#{tracked_count} tracked, #{paths.size - tracked_count} named build products) -> #{OUT.relative_path_from(ROOT)}"
