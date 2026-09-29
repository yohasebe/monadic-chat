#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that the packaged archives carry exactly the payload that
# stage_docker_payload.rb assembled — no more, no less.
#
# Staging alone is not a guarantee: electron-builder could be pointed back at
# the working tree, a filter could be widened, or a stale staging directory
# could be packaged. This reads the archives that actually ship and compares
# them against the manifest the staging step wrote.
#
# An extra file is the failure this exists to catch: releases beta.21 through
# beta.32 carried benchmark logs, __pycache__ and rspec state, each naming
# absolute paths on the build machine.

require 'json'
require 'open3'
require 'pathname'
require 'set'
require 'tmpdir'

ROOT = Pathname.new(File.expand_path('..', __dir__))
DIST = Pathname.new(ARGV[0] || ROOT.join('dist'))
MANIFEST = ROOT.join('build/app-payload.manifest')
ASAR_MANIFEST = ROOT.join('build/app-asar.manifest')
ASAR_MODULES = ROOT.join('build/app-asar.modules')
# node resolves @electron/asar from here; tests point it at the real checkout.
NODE_MODULES = ENV['MONADIC_NODE_MODULES'] || ROOT.join('node_modules').to_s

unless MANIFEST.file?
  abort "[verify_bundle_payload] no manifest at #{MANIFEST.relative_path_from(ROOT)}; run stage_docker_payload.rb first."
end

expected = MANIFEST.read.split("\n").reject(&:empty?).to_set

# A symlink to a directory survives as a link in the mac zip but is copied out
# as its contents on Windows, which cannot store links. Both carry the same
# payload, so the dereferenced form is an accepted alternative: it widens what
# may appear without widening what must appear.
SYMLINK_LIST = ROOT.join('build/app-payload.symlinks')
symlinks = {}
if SYMLINK_LIST.file?
  SYMLINK_LIST.read.split("\n").reject(&:empty?).each do |line|
    link, target = line.split("\t", 2)
    next unless link && target

    symlinks[link] = Pathname.new(File.dirname(link)).join(target).cleanpath.to_s
  end
end

dereferenced = Set.new
symlinks.each do |link, resolved|
  expected.each do |e|
    dereferenced << e.sub(%r{\A#{Regexp.escape(resolved)}/}, "#{link}/") if e.start_with?("#{resolved}/")
  end
end
allowed = expected | dereferenced

# Archive -> the directory holding app.asar and the app/ payload inside it.
RESOURCES = {
  mac: 'Monadic Chat.app/Contents/Resources/',
  win: 'resources/',
  appimage: 'resources/'
}.freeze

def archives(dist)
  found = []
  dist.glob('Monadic*-arm64.zip').each { |z| found << [z, :mac] }
  dist.glob('Monadic.Chat.Setup.*.zip').each { |z| found << [z, :win] }
  dist.glob('*.AppImage').each { |z| found << [z, :appimage] }
  found.sort_by { |z, _| z.basename.to_s }
end

# Every entry path, with directories ending in '/'.
def entries(file, kind)
  if kind == :appimage
    out, status = Open3.capture2('7zz', 'l', '-slt', '-ba', file.to_s)
    abort "[verify_bundle_payload] could not read #{file} (7zz is needed for AppImages)" unless status.success?
    out.split(/\n\n+/).filter_map do |block|
      path = block[/^Path = (.+)$/, 1]
      next unless path

      block.include?("\nFolder = +") ? "#{path}/" : path
    end
  else
    out = `unzip -Z1 "#{file}" 2>/dev/null`
    abort "[verify_bundle_payload] could not read #{file}" unless $?.success?
    out.split("\n")
  end
end

# Unpacks the resources directory (app.asar and the app/ payload beside it)
# and returns its path, or nil when the archive has none. -snld: 7zz refuses
# a relative link such as vendor/css/fonts -> ../fonts without it; the link
# stays inside the payload and the path checks above already account for it.
def extract_resources(file, kind, into)
  res = RESOURCES.fetch(kind)
  ok = if kind == :appimage
         system('7zz', 'x', '-snld', "-o#{into}", file.to_s, "#{res}*", out: File::NULL, err: File::NULL)
       else
         system('unzip', '-q', '-o', file.to_s, "#{res}*", '-d', into, out: File::NULL, err: File::NULL)
       end
  dir = File.join(into, res)
  ok && File.file?(File.join(dir, 'app.asar')) ? dir : nil
end

# Files (not directories) inside an asar, read from its header by the same
# library electron-builder packs it with, plus name@version for each package
# directory (read from its package.json). Lines are "F path" and "P name@ver".
ASAR_LISTER = <<~'JS'
  const asar = require('@electron/asar');
  const archive = process.argv[1];
  const header = asar.getRawHeader(archive).header;
  const out = [];
  const roots = new Set();
  (function walk(node, prefix) {
    for (const [name, child] of Object.entries(node.files || {})) {
      const p = prefix ? `${prefix}/${name}` : name;
      if (child.files) walk(child, p); else out.push('F ' + p);
      const segs = p.split('/');
      const i = segs.lastIndexOf('node_modules');
      if (i >= 0 && i < segs.length - 1) {
        const take = segs[i + 1].startsWith('@') ? i + 3 : i + 2;
        if (segs.length >= take) roots.add(segs.slice(0, take).join('/'));
      }
    }
  })(header, '');
  for (const root of roots) {
    try {
      const pkg = JSON.parse(asar.extractFile(archive, root + '/package.json').toString());
      out.push(`P ${pkg.name}@${pkg.version}`);
    } catch (e) {
      out.push(`P ${root}@unreadable`);
    }
  }
  if (process.argv[2]) asar.extractAll(archive, process.argv[2]);
  process.stdout.write(out.join('\n'));
JS

# [files, packages] inside an asar, its contents unpacked into extract_to.
def asar_contents(asar_path, extract_to)
  out, err, status = Open3.capture3({ 'NODE_PATH' => NODE_MODULES }, 'node', '-e', ASAR_LISTER, asar_path, extract_to)
  abort "[verify_bundle_payload] could not list #{asar_path}: #{err.strip}" unless status.success?
  lines = out.split("\n")
  [lines.filter_map { |l| l.delete_prefix('F ') if l.start_with?('F ') },
   lines.filter_map { |l| l.delete_prefix('P ') if l.start_with?('P ') }.to_set]
end

# Tracked files must carry the bytes committed at HEAD when staging ran
# (build/app-tracked.blobs). The blob IDs of the packed files come from git
# itself, so the comparison uses git's own definition of "the same file".
# Build products (vendor assets, the JS bundle, the help database) are not
# tracked and not listed there; their own gates check them.
BLOBS = ROOT.join('build/app-tracked.blobs')

# {repo path => packed file on disk} -> repo paths whose bytes differ.
def blob_mismatches(files, recorded)
  checked = files.select { |repo, disk| recorded.key?(repo) && File.file?(disk) && !File.symlink?(disk) }
  return [] if checked.empty?

  out, err, status = Open3.capture3('git', '-C', ROOT.to_s, 'hash-object', '--no-filters', '--stdin-paths',
                                    stdin_data: checked.map(&:last).join("\n") + "\n")
  abort "[verify_bundle_payload] git hash-object failed: #{err.strip}" unless status.success?
  checked.map(&:first).zip(out.split("\n")).reject { |repo, sha| recorded[repo] == sha }.map(&:first).sort
end

# electron-builder rewrites the package.json it packs: it keeps the fields the
# app reads at run time and drops scripts, devDependencies and the build
# config. So the packed file is compared field by field: each field it holds
# must exist in the committed file with the same value.
def package_json_problem(packed_path, blob)
  return 'package.json is missing from app.asar' unless packed_path && File.file?(packed_path)
  return 'package.json has no recorded blob' unless blob

  committed, status = Open3.capture2('git', '-C', ROOT.to_s, 'cat-file', 'blob', blob)
  return "could not read the committed package.json (#{blob})" unless status.success?

  packed = JSON.parse(File.read(packed_path))
  source = JSON.parse(committed)
  changed = packed.keys.reject { |k| source.key?(k) && source[k] == packed[k] }
  changed.empty? ? nil : "package.json fields differ from the commit: #{changed.sort.join(', ')}"
rescue JSON::ParserError => e
  "package.json does not parse: #{e.message}"
end

# What electron-builder itself places beside app.asar and the payload.
RESOURCE_ALLOWED = %w[app app.asar app-update.yml].freeze
MAC_RESOURCE_ALLOWED = [/\A[A-Za-z0-9_]+\.lproj\z/, /\Aicon\.icns\z/].freeze

# Libraries the AppImage toolset adds under usr/lib (electron-builder's
# appimage@1.0.3 runtime), and the app icon at each size it is rendered in.
APPIMAGE_USR = %r{\Ausr(?:/(?:lib(?:/lib(?:Xss\.so\.1|Xtst\.so\.6|appindicator3\.so\.1|gconf-2\.so\.4|indicator3\.so\.7|notify\.so\.4)(?:\.[0-9.]+)?)?|share(?:/icons(?:/hicolor(?:/[0-9]+x[0-9]+(?:/apps(?:/monadic-chat\.png)?)?)?)?)?))?\z}

# Files electron-builder adds from package.json on top of app.asar, recorded by
# staging as "kind<TAB>destination<TAB>source": "resources" entries sit under
# the resources directory of every package (LICENSE, README.md), "linux"
# entries in the AppImage (the AppStream metainfo). Each must be present with
# the committed contents of its source. The record is required: without it an
# entry that failed to ship would go unnoticed.
EXTRA = ROOT.join('build/app-extra')

def extra_entries(kind)
  EXTRA.read.split("\n").reject(&:empty?).map { |l| l.split("\t", 3) }
       .select { |k, _, _| k == kind }.to_h { |_, dest, source| [dest, source] }
end

def linux_extra_allowed?(entry, extra)
  extra.key?(entry) || extra.keys.any? { |dest| dest.start_with?("#{entry}/") }
end

# squashfs superblock: every file owned by uid/gid 0, and no xattr table (so
# no build-machine attributes such as download origins travel along).
def appimage_superblock_problems(file)
  h = File.binread(file, 64)
  off = h[40, 8].unpack1('Q<') + h[58, 2].unpack1('S<') * h[60, 2].unpack1('S<')
  sb = File.binread(file, 96, off)
  return ['squashfs superblock not found after the runtime'] unless sb && sb[0, 4] == 'hsqs'

  problems = []
  id_count = sb[26, 2].unpack1('S<')
  ptr = File.binread(file, 8, off + sb[48, 8].unpack1('Q<')).unpack1('Q<')
  hdr = File.binread(file, 2, off + ptr).unpack1('S<')
  if (hdr & 0x8000).zero?
    problems << 'squashfs id table is compressed; ownership not checked'
  else
    ids = File.binread(file, hdr & 0x7fff, off + ptr + 2).unpack('L<*').first(id_count)
    problems << "squashfs owners are #{ids.inspect}, expected [0]" unless ids == [0]
  end
  problems << 'squashfs carries an xattr table' unless sb[56, 8].unpack1('Q<') == 0xFFFFFFFFFFFFFFFF
  problems
end

targets = archives(DIST)
if targets.empty?
  abort "[verify_bundle_payload] no packaged archive found in #{DIST}; nothing was checked."
end

failures = []

[ASAR_MANIFEST, ASAR_MODULES].each do |f|
  abort "[verify_bundle_payload] no #{f.relative_path_from(ROOT)}; run stage_docker_payload.rb first." unless f.file?
end
asar_expected = ASAR_MANIFEST.read.split("\n").reject(&:empty?).to_set
modules_allowed = ASAR_MODULES.read.split("\n").reject(&:empty?).to_set
abort "[verify_bundle_payload] no #{BLOBS.relative_path_from(ROOT)}; run stage_docker_payload.rb first." unless BLOBS.file?
abort "[verify_bundle_payload] no #{EXTRA.relative_path_from(ROOT)}; run stage_docker_payload.rb first." unless EXTRA.file?
resource_extra = extra_entries('resources')
linux_extra = extra_entries('linux')
recorded_blobs = BLOBS.read.split("\n").reject(&:empty?).to_h { |l| l.split("\t", 2).reverse }

targets.each do |zip, kind|
  rel = zip.relative_path_from(DIST).to_s
  res = RESOURCES.fetch(kind)
  prefix = %r{\A#{Regexp.escape(res)}app/}
  all = entries(zip, kind)

  # What sits directly beside app.asar is electron-builder's own output.
  beside = all.select { |e| e.start_with?(res) }.filter_map { |e| e.delete_prefix(res).split('/').first }.uniq
  unexpected = beside.reject do |n|
    RESOURCE_ALLOWED.include?(n) || (kind == :mac && MAC_RESOURCE_ALLOWED.any? { |re| n.match?(re) })
  end
  failures << "#{rel}: unexpected entries beside app.asar: #{unexpected.sort.join(', ')}" unless unexpected.empty?

  if kind == :appimage
    extra = linux_extra
    stray = all.map { |e| e.chomp('/') }.select { |e| e.start_with?('usr') }
               .reject { |e| e.match?(APPIMAGE_USR) || linux_extra_allowed?(e, extra) }
    failures << "#{rel}: unexpected files under usr/: #{stray.first(10).join(', ')}" unless stray.empty?
    appimage_superblock_problems(zip).each { |pr| failures << "#{rel}: #{pr}" }

    Dir.mktmpdir('verify_extra') do |tmp|
      placed = {}
      extra.each do |dest, source|
        unless all.include?(dest)
          failures << "#{rel}: #{dest} (from #{source}) is missing"
          next
        end
        system('7zz', 'x', "-o#{tmp}", zip.to_s, dest, out: File::NULL, err: File::NULL)
        placed[source] = File.join(tmp, dest)
      end
      blob_mismatches(placed, recorded_blobs).each do |source|
        failures << "#{rel}: #{extra.key(source)} differs from the committed #{source}"
      end
      unrecorded = placed.keys.reject { |source| recorded_blobs.key?(source) }
      failures << "#{rel}: no recorded blob for #{unrecorded.join(', ')}" unless unrecorded.empty?
    end
  end

  # The app itself: own files must be exactly the tracked ones; dependencies
  # only the packages npm installs for production.
  # The app itself: own files must be exactly the tracked ones, with their
  # committed contents; dependencies only the packages npm installs for
  # production. The payload beside it must hold the committed bytes too.
  Dir.mktmpdir('verify_resources') do |tmp|
    dir = extract_resources(zip, kind, tmp)
    if dir.nil?
      failures << "#{rel}: no app.asar found at #{res}app.asar"
      next
    end
    unpacked = File.join(tmp, 'asar-contents')
    files, pkgs = asar_contents(File.join(dir, 'app.asar'), unpacked)
    own = files.reject { |f| f.start_with?('node_modules/') }.to_set
    extra_own = (own - asar_expected).to_a.sort
    missing_own = (asar_expected - own).to_a.sort
    failures << "#{rel}: app.asar holds #{extra_own.size} untracked file(s): #{extra_own.first(10).join(', ')}" unless extra_own.empty?
    failures << "#{rel}: app.asar lacks #{missing_own.size} tracked file(s): #{missing_own.first(10).join(', ')}" unless missing_own.empty?
    foreign = (pkgs - modules_allowed).to_a.sort
    failures << "#{rel}: app.asar holds packages outside the production dependencies: #{foreign.first(10).join(', ')}" unless foreign.empty?

    packed = own.to_h { |f| [f, File.join(unpacked, f)] }
    Dir.glob(File.join(dir, 'app', '{docker,bin}', '**', '*'), File::FNM_DOTMATCH).each do |disk|
      repo = disk.delete_prefix(File.join(dir, 'app') + '/')
      # A link Windows stored as its target's contents maps back to the target.
      symlinks.each { |link, resolved| repo = repo.sub(%r{\A#{Regexp.escape(link)}/}, "#{resolved}/") }
      packed[repo] = disk
    end
    resource_extra.each { |dest, source| packed[source] = File.join(dir, dest) }
    pj = package_json_problem(packed.delete('package.json'), recorded_blobs['package.json'])
    failures << "#{rel}: #{pj}" if pj
    changed = blob_mismatches(packed, recorded_blobs)
    unless changed.empty?
      failures << "#{rel}: #{changed.size} tracked file(s) differ from the committed version"
      changed.first(15).each { |e| failures << "    ~ #{e}" }
    end
    compared = packed.count { |repo, disk| recorded_blobs.key?(repo) && File.file?(disk) && !File.symlink?(disk) }
    # Every recorded file has to be compared; comparing none would read as a pass.
    # package.json is compared field by field above, and the linux.extraFiles
    # sources only exist in the AppImages (checked there).
    skipped = ['package.json', *linux_extra.values].count { |p| recorded_blobs.key?(p) }
    expected_compared = recorded_blobs.size - skipped
    if compared < expected_compared
      failures << "#{rel}: compared #{compared} of #{expected_compared} recorded tracked files with the commit"
    end
    puts "[verify_bundle_payload] #{rel}: app.asar #{own.size} own files, #{pkgs.size} packages; " \
         "#{compared} tracked files compared with the commit"
  end

  # Under resources/app only the payload trees and the recorded extras.
  app_dir = "#{res}app/"
  loose = all.reject { |e| e.end_with?('/') || e.start_with?('__MACOSX/') }
             .select { |e| e.start_with?(app_dir) }
             .map { |e| e.delete_prefix(res) }
             .reject { |e| e.start_with?('app/docker/', 'app/bin/') || resource_extra.key?(e) }
             .reject { |e| e.split('/').last.to_s.start_with?('._') }
  failures << "#{rel}: unexpected files in #{app_dir}: #{loose.first(10).join(', ')}" unless loose.empty?
  resource_extra.each_key do |dest|
    failures << "#{rel}: #{res}#{dest} is missing" unless all.include?("#{res}#{dest}")
  end

  # Skip directory entries and the resource forks the mac zip carries.
  payload = all
            .reject { |e| e.end_with?('/') }
            .reject { |e| e.start_with?('__MACOSX/') }
            .grep(prefix)
            .map { |e| e.sub(prefix, '') }
            .reject { |e| e.split('/').last.to_s.start_with?('._') }
            .select { |e| e.start_with?('docker/', 'bin/') }
            .to_set

  extra = (payload - allowed).to_a.sort
  # A symlink the archive stored as its contents instead is still present.
  satisfied = symlinks.keys.select { |link| payload.any? { |e| e.start_with?("#{link}/") } }.to_set
  missing = (expected - payload - satisfied).to_a.sort

  unless extra.empty?
    failures << "#{rel}: #{extra.size} file(s) not in the staged payload"
    extra.first(15).each { |e| failures << "    + #{e}" }
    failures << "    … and #{extra.size - 15} more" if extra.size > 15
  end

  unless missing.empty?
    failures << "#{rel}: #{missing.size} staged file(s) did not reach the archive"
    missing.first(10).each { |e| failures << "    - #{e}" }
  end

  puts "[verify_bundle_payload] #{rel}: #{payload.size} payload files" if extra.empty? && missing.empty?
end

if failures.empty?
  puts "[verify_bundle_payload] OK: #{targets.size} archive(s) match the staged payload (#{expected.size} files)."
  exit 0
end

warn '[verify_bundle_payload] FAILED:'
failures.each { |f| warn "  #{f}" }
exit 1
