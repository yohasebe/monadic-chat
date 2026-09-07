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
require 'pathname'

ROOT = Pathname.new(File.expand_path('..', __dir__))
OUT = ROOT.join('build/app-payload')
MANIFEST = ROOT.join('build/app-payload.manifest')
SYMLINKS = ROOT.join('build/app-payload.symlinks')

# Generated at build time, required at run time. Globs are relative to ROOT.
REQUIRED_BUILD_PRODUCTS = [
  'docker/services/ruby/public/vendor/**/*',
  'docker/services/ruby/public/js/monadic.bundle.min.js',
  'docker/services/ruby/help_data/help_db.json'
].freeze

# The directories that ship inside the app, each mirrored under OUT by name.
SHIPPED_TREES = %w[docker bin].freeze

def tracked_paths
  out = `git -C "#{ROOT}" ls-files -z #{SHIPPED_TREES.join(' ')}`
  raise 'git ls-files failed' unless $?.success?

  out.split("\0").reject(&:empty?)
end

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
