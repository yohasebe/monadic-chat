#!/usr/bin/env ruby
# frozen_string_literal: true

# EN/JA Documentation Parity Checker
#
# Compares heading-level structure between docs/ and docs/ja/ counterpart
# files.  Since EN headings are in English and JA headings are in Japanese,
# text matching is not possible.  Instead we compare the ordered sequence
# of heading levels (##, ###, ####).  When the sequences diverge, the file
# is flagged so a human can review which section is missing or extra.
#
# Usage:
#   ruby scripts/lint/check_docs_parity.rb
#   npm run test:docs-parity

require "pathname"

ROOT    = Pathname.new(__dir__).join("..", "..").realpath
DOCS_EN = ROOT.join("docs")
DOCS_JA = ROOT.join("docs", "ja")

# Directories to skip (no JA counterparts expected)
SKIP_DIRS = %w[assets].freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Extract an ordered list of { level:, text:, line: } from a markdown file.
def extract_headings(file)
  return [] unless file.exist?

  headings = []
  file.each_line.with_index(1) do |line, lineno|
    if (m = line.match(/^(\#{2,4})\s+(.+)$/))
      headings << { level: m[1].length, text: m[2].strip, line: lineno }
    end
  end
  headings
end

# Build a compact level sequence string for quick equality check.
#   e.g. "2,3,3,4,2,3"
def level_sequence(headings)
  headings.map { |h| h[:level] }.join(",")
end

# Produce a human-readable diff between two heading lists.
# Uses a simple LCS (longest-common-subsequence) on the level arrays
# and reports insertions / deletions with surrounding context.
def diff_levels(en_headings, ja_headings)
  en_levels = en_headings.map { |h| h[:level] }
  ja_levels = ja_headings.map { |h| h[:level] }

  # LCS table
  n = en_levels.size
  m = ja_levels.size
  dp = Array.new(n + 1) { Array.new(m + 1, 0) }
  (1..n).each do |i|
    (1..m).each do |j|
      dp[i][j] = if en_levels[i - 1] == ja_levels[j - 1]
                   dp[i - 1][j - 1] + 1
                 else
                   [dp[i - 1][j], dp[i][j - 1]].max
                 end
    end
  end

  # Back-trace to produce diff operations
  ops = []
  i = n
  j = m
  while i.positive? || j.positive?
    if i.positive? && j.positive? && en_levels[i - 1] == ja_levels[j - 1] && dp[i][j] == dp[i - 1][j - 1] + 1
      ops.unshift({ type: :match, en_idx: i - 1, ja_idx: j - 1 })
      i -= 1
      j -= 1
    elsif j.positive? && (i.zero? || dp[i][j - 1] >= dp[i - 1][j])
      ops.unshift({ type: :ja_extra, ja_idx: j - 1 })
      j -= 1
    else
      ops.unshift({ type: :en_extra, en_idx: i - 1 })
      i -= 1
    end
  end

  ops
end

# Format a heading for display:  "## Heading Text  (line 42)"
def fmt(heading)
  prefix = "#" * heading[:level]
  "#{prefix} #{heading[:text]}  (L#{heading[:line]})"
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Collect all EN markdown files (excluding ja/ sub-tree and asset dirs)
en_files = Dir.glob(DOCS_EN.join("**", "*.md").to_s)
             .map { |f| Pathname.new(f) }
             .reject { |f| f.to_s.start_with?(DOCS_JA.to_s) }
             .reject { |f| SKIP_DIRS.any? { |d| f.to_s.include?("/#{d}/") } }
             .sort

checked        = 0
mismatched     = []
missing_ja     = []

en_files.each do |en_file|
  rel     = en_file.relative_path_from(DOCS_EN)
  ja_file = DOCS_JA.join(rel)

  unless ja_file.exist?
    missing_ja << rel.to_s
    next
  end

  checked += 1

  en_h = extract_headings(en_file)
  ja_h = extract_headings(ja_file)

  next if level_sequence(en_h) == level_sequence(ja_h)

  ops = diff_levels(en_h, ja_h)

  extras = ops.reject { |o| o[:type] == :match }
  next if extras.empty?

  mismatched << { file: rel.to_s, en_headings: en_h, ja_headings: ja_h, ops: ops }
end

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

puts "EN/JA Documentation Parity Check"
puts "=" * 60
puts "Files checked: #{checked}"
puts

if missing_ja.any?
  puts "Missing JA counterparts (#{missing_ja.size}):"
  missing_ja.each { |f| puts "  - docs/ja/#{f}" }
  puts
end

if mismatched.empty?
  puts "All heading structures match between EN and JA."
  exit 0
end

puts "Heading structure mismatches found in #{mismatched.size} file(s):"
puts

mismatched.each do |entry|
  file = entry[:file]
  en_h = entry[:en_headings]
  ja_h = entry[:ja_headings]
  ops  = entry[:ops]

  en_count = en_h.size
  ja_count = ja_h.size

  puts "  #{file}  (EN: #{en_count} headings, JA: #{ja_count} headings)"
  puts "  " + "-" * 56

  ops.each do |op|
    case op[:type]
    when :en_extra
      h = en_h[op[:en_idx]]
      puts "    [EN only]  #{fmt(h)}"
    when :ja_extra
      h = ja_h[op[:ja_idx]]
      puts "    [JA only]  #{fmt(h)}"
    end
  end
  puts
end

puts "To fix: add missing sections to the counterpart file."
puts "EN/JA documentation must maintain structural parity."
exit 1
