# frozen_string_literal: true

require 'json'
require 'open3'
require 'pathname'
require 'set'

# Decides whether a help database dump is safe to ship.
#
# The dump is generated, not tracked, so nothing else checks what is in it.
# Three ways it goes wrong: `rake help:build_internal` leaves a dump with
# docs_dev/ in it and a later build reuses it (SKIP_HELP_DB=true); a document is
# deleted from the tree while the dump still carries its text; or the generator
# fails part-way and leaves a dump with no content in it. All three ship
# silently, so they are checked rather than trusted.
#
# The logic lives here, parameterised by root and dump path, so the packaging
# scripts and the lint self-test can exercise the same code — the self-test
# against a fixture, without needing a generated dump or touching build output.
module HelpDumpGuard
  REQUIRED_COLLECTIONS = %w[help_docs help_items].freeze

  module_function

  # Returns an array of problem strings. Empty means the dump may ship.
  # A dump that does not exist is not a problem here: the caller decides
  # whether a missing dump is acceptable.
  def problems(dump_path:, root:)
    dump = Pathname(dump_path.to_s)
    return [] unless dump.file?

    begin
      data = JSON.parse(dump.read)
    rescue JSON::ParserError => e
      return ["help dump is not valid JSON: #{e.message}"]
    end

    collections = data.is_a?(Hash) ? data['collections'] : nil
    shape = shape_problems(collections)
    return shape unless shape.empty?

    internal_problems(collections) + stale_problems(collections, root)
  end

  # An empty or truncated dump passes every content check by having no content
  # to fail on, so the shape is checked before anything is counted.
  def shape_problems(collections)
    return ['help dump has no "collections" object'] unless collections.is_a?(Hash)

    REQUIRED_COLLECTIONS.flat_map do |name|
      coll = collections[name]
      next ["help dump is missing the #{name} collection"] unless coll.is_a?(Hash)

      points = coll['points']
      next ["help dump has no points array in #{name}"] unless points.is_a?(Array)
      next ["help dump has an empty #{name} collection"] if points.empty?

      point_problems(name, points)
    end
  end

  # A point the guard cannot read is a point it cannot clear for shipping, so
  # malformed points are refused rather than quietly skipped. Nothing valid is
  # lost by being strict here: every point the generator writes carries an id,
  # a payload hash and a boolean is_internal, and DumpLoader reads the same
  # fields, so a dump with unreadable points would not load either.
  def point_problems(name, points)
    problems = []

    malformed = points.count { |pt| !valid_point?(pt) }
    if malformed.positive?
      problems << "help dump has #{malformed} malformed point(s) in #{name}; " \
                  'each needs an id and a payload with a boolean is_internal'
    end

    if name == 'help_docs'
      pathless = points.count { |pt| valid_point?(pt) && pt.dig('payload', 'file_path').to_s.empty? }
      problems << "help dump has #{pathless} help_docs point(s) with no file_path" if pathless.positive?
    end

    problems
  end

  def valid_point?(point)
    return false unless point.is_a?(Hash)
    return false if point['id'].nil?

    payload = point['payload']
    payload.is_a?(Hash) && [true, false].include?(payload['is_internal'])
  end

  def internal_problems(collections)
    return [] unless collections.is_a?(Hash)

    internal = collections.sum do |_name, coll|
      points = coll.is_a?(Hash) ? coll['points'] : nil
      points.is_a?(Array) ? points.count { |pt| pt.is_a?(Hash) && pt.dig('payload', 'is_internal') } : 0
    end
    return [] if internal.zero?

    ["help dump carries #{internal} internal point(s) from docs_dev/"]
  end

  def stale_problems(collections, root)
    return [] unless collections.is_a?(Hash)

    sources = source_paths(collections)
    return [] if sources.empty?

    tracked = tracked_paths(root)
    return ['cannot list the tracked documents with git, so the dump cannot be cleared'] if tracked.nil?

    stale = sources.reject { |rel| tracked.include?(rel) && present?(root, rel) }
    return [] if stale.empty?

    ["help dump names #{stale.size} document(s) that git does not track:\n    " +
     stale.first(10).join("\n    ")]
  end

  # Membership is decided by git, not by the working tree. The shipped dump
  # carried docs_dev/external_apis/README.md, which .gitignore excludes but
  # which exists on disk — the generator read the working tree, so being
  # present was enough. Asking git instead refuses anything gitignored or
  # simply untracked, and git's paths are already case-exact, which the
  # working tree is not on macOS.
  def tracked_paths(root)
    out, status = Open3.capture2(
      'git', '-C', root.to_s, 'ls-files', '-z', '--', 'docs', 'README.md', 'CHANGELOG.md'
    )
    return nil unless status.success?

    out.split("\x00").reject(&:empty?).to_set
  rescue SystemCallError
    nil
  end

  # A tracked path that was deleted from the working tree would still be
  # listed by git while its content no longer exists, so require both.
  def present?(root, rel)
    Pathname(root.to_s).join(rel).file?
  rescue SystemCallError
    false
  end

  # Root documents (README.md, CHANGELOG.md) are stored with a bare file name
  # and `is_root_doc`; everything else is stored relative to docs/. Prefixing
  # every path with docs/ conflates the root README with docs/README.md and
  # sends the root CHANGELOG to docs/CHANGELOG.md, which does not exist — the
  # published page is the lowercase docs/changelog.md.
  def source_paths(collections)
    points = collections.is_a?(Hash) ? collections.dig('help_docs', 'points') : nil
    return [] unless points.is_a?(Array)

    # Internal points are reported by internal_problems and are relative to
    # docs_dev/, so resolving them against docs/ here would only add noise to a
    # dump that is already being refused.
    points.reject { |pt| pt.is_a?(Hash) && pt.dig('payload', 'is_internal') }
          .filter_map { |pt| source_path(pt) }.uniq
  end

  def source_path(point)
    return nil unless point.is_a?(Hash)

    payload = point['payload']
    return nil unless payload.is_a?(Hash)

    rel = payload['file_path']
    return nil if rel.nil? || rel.to_s.empty?

    rel = rel.to_s
    return rel if payload.dig('metadata', 'is_root_doc')
    return rel if rel.start_with?('docs/')

    "docs/#{rel}"
  end
end

if __FILE__ == $PROGRAM_NAME
  dump = ARGV[0]
  root = ARGV[1] || Dir.pwd
  abort 'usage: help_dump_guard.rb <help_db.json> [repo_root]' if dump.nil? || dump.empty?

  abort "[help_dump_guard] no dump at #{dump}" unless File.file?(dump)

  found = HelpDumpGuard.problems(dump_path: dump, root: root)
  if found.empty?
    puts "[help_dump_guard] OK — #{dump} is safe to ship."
  else
    abort "[help_dump_guard] refusing to ship #{dump}:\n  " + found.join("\n  ") +
          "\n  Regenerate it with `rake help:build` (public documentation only)."
  end
end
