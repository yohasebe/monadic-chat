#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: personal home-directory paths in source code.
#
# Catches the failure mode that produced the jupyter_helper.rb defect
# (dev-mode shared volume hard-coded to /Users/yohasebe/monadic/data).
# Personal paths work for the original author and silently break for
# everyone else; the canonical replacement is
# Monadic::Utils::Environment.data_path (or Dir.home / File.expand_path
# for general-purpose paths).
#
# What we flag:
#   - /Users/<name>/...          (macOS home)
#   - /home/<name>/...           (Linux home, except a small allow-list)
#   - C:\Users\<name>\...        (Windows home)
#
# What we DO NOT flag:
#   - "~/..." (tilde — host-portable)
#   - Dir.home, ENV['HOME'], File.expand_path('~/...')
#   - "/monadic/data" / "/monadic/..." — these are the container-side
#     canonical paths and have their own lint rule (check_data_path_literals.rb)
#
# Allow-list strategy:
#   - test/spec files where personal paths are deliberate fixtures
#   - documentation example lines starting with "#" or "//"
#   - the lint config files themselves
#
# Output mode:
#   - Default: print every violation as "path:line: content" and exit
#     with status equal to the violation count (capped at 1 for CI).
#   - With --baseline N: exit 0 if violations <= N (used for warn-only
#     rollout while the codebase has known violations).

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

# Roots where the rule applies, each with the fewest files a scan of it may
# read. Tests/specs are intentionally excluded because realistic fixtures
# sometimes need explicit personal paths.
#
# A scan that reads nothing also finds no violations, so a renamed root or a
# misresolved ROOT would pass silently. The floors sit about 20% below the
# current counts (app 12, lib 205, scripts 20, public/js 91, python 24,
# extractor 5, embeddings 5, privacy 10); lower one when files are genuinely
# removed, and drop the entry when a root is retired on purpose.
SCAN_ROOTS = {
  'app' => 10,
  'docker/services/ruby/lib' => 165,
  'docker/services/ruby/scripts' => 16,
  'docker/services/ruby/public/js' => 72,
  'docker/services/python/scripts' => 19,
  'docker/services/extractor' => 4,
  'docker/services/embeddings' => 4,
  'docker/services/privacy' => 8
}.freeze

ALLOWED_EXTENSIONS = %w[.rb .js .mjs .ts .py .sh .erb .mdsl .yml .yaml].freeze

# Files that legitimately mention personal paths (e.g. lint scripts
# describing the patterns themselves, or compatibility shims).
ALLOWLIST_PATHS = %w[
  scripts/lint/check_personal_paths.rb
].freeze

# Paths whose literal personal-path mentions are documented and accepted.
# Each entry is a [pathname, regex-or-substring] pair; a violation
# matches the allowlist when both file path AND content match. This is
# the seam for the deprecate-then-fix workflow — known historical
# violations live here while migrations land. Empty after H6: every
# known occurrence has either been migrated or is owned by this script
# itself.
ACCEPTED_VIOLATIONS = [].freeze

PERSONAL_PATH_PATTERNS = [
  %r{/Users/[A-Za-z0-9_.-]+/},
  %r{/home/[A-Za-z0-9_.-]+/},
  %r{C:\\Users\\[A-Za-z0-9_.-]+\\}
].freeze

def each_target_file
  return enum_for(:each_target_file) unless block_given?

  SCAN_ROOTS.each_key do |rel_root|
    Dir.glob(ROOT.join(rel_root, '**', '*')).each do |path|
      next unless File.file?(path)
      next unless ALLOWED_EXTENSIONS.include?(File.extname(path))
      yield rel_root, Pathname.new(path)
    end
  end
end

def relative_path(absolute)
  Pathname.new(absolute).relative_path_from(ROOT).to_s
end

def allowed_violation?(rel_path, line_text)
  return true if ALLOWLIST_PATHS.include?(rel_path)
  ACCEPTED_VIOLATIONS.any? do |allowed_path, marker|
    next false unless allowed_path == rel_path
    if marker.is_a?(Regexp)
      line_text.match?(marker)
    else
      line_text.include?(marker)
    end
  end
end

baseline = nil
if ARGV.include?('--baseline')
  idx = ARGV.index('--baseline')
  baseline = ARGV[idx + 1].to_i
end

violations = []
scanned = Hash.new(0)
each_target_file do |rel_root, path|
  scanned[rel_root] += 1
  rel = relative_path(path)
  text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
  text.each_line.with_index do |line, idx|
    PERSONAL_PATH_PATTERNS.each do |re|
      next unless line.match?(re)
      next if allowed_violation?(rel, line)
      violations << { path: rel, line: idx + 1, text: line.rstrip }
    end
  end
end

# Checked before the violation count: a short scan is a failure even when
# --baseline would otherwise accept the result.
short = SCAN_ROOTS.select { |rel_root, floor| scanned[rel_root] < floor }
puts "[lint:personal_paths] scanned #{scanned.values.sum} file(s) under #{SCAN_ROOTS.size} root(s)"
unless short.empty?
  short.each do |rel_root, floor|
    puts "  #{rel_root}: scanned #{scanned[rel_root]} file(s), expected at least #{floor}"
  end
  exit 1
end

if violations.empty?
  puts '[lint:personal_paths] OK — no personal home-directory paths found.'
  exit 0
end

puts "[lint:personal_paths] #{violations.size} violation(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
end

if baseline && violations.size <= baseline
  puts "[lint:personal_paths] within baseline (<= #{baseline}); exiting 0."
  exit 0
end

exit 1
