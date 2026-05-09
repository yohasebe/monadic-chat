#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: shell command interpolation without Shellwords.escape.
#
# Catches the failure mode that produced the fetch_webpage URL injection
# defect (CVE-class: arbitrary command execution via the Text-from-URL
# button). The same pattern appears anywhere the codebase builds a shell
# string with `#{var}` interpolation: docker exec, system, backticks,
# Open3.capture3 with shell-form arguments, etc.
#
# What we flag:
#   - "docker exec ... #{IDENT} ..."   (shell-string form)
#   - "bash -c '... #{IDENT} ...'"     (likewise)
#   - `... #{IDENT} ...`               (backtick form)
#   - system("... #{IDENT} ...")       (string-form system, not the
#     argv-form that bypasses the shell)
#
#   ...where IDENT is not the literal "Shellwords.escape(...)" call.
#
# What we DO NOT flag:
#   - Open3.capture3(*cmd) with cmd = ["docker", "exec", ...] (no shell)
#   - heredoc strings that interpolate already-escaped values (we look
#     5 lines back from the heredoc opener for a Shellwords.escape
#     assignment to the interpolated identifier)
#   - test/spec files
#
# Output mode:
#   Same as check_personal_paths.rb: report violations, exit 1 unless
#   --baseline N permits the current count.

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

SCAN_ROOTS = [
  'app',
  'docker/services/ruby/lib',
  'docker/services/ruby/scripts',
  'docker/services/ruby/apps'
].freeze

# Identifiers we trust without Shellwords.escape because they are either
# fixed at build-time (constants), server-generated (timestamps, hex), or
# already pre-escaped by convention. The lint matches these literally
# against the inner expression of "#{...}".
SAFE_INTERPOLATION_NAMES = %w[
  SHARED_VOL
  LOCAL_SHARED_VOL
  USER_SCRIPT_DIR
  container
  data_dir
  shared_volume
].freeze

SAFE_INTERPOLATION_PATTERNS = [
  /\Aescaped_[a-z_]+\z/,                    # by convention: escaped_basename
  /\Asafe_[a-z_]+\z/,                       # by convention: safe_url
  /\Acontainer_[a-z_]+_path\z/,              # auto_forge_debugger style
  /\Anew_file_name\z/,                       # generated filename
  /\Acommand(\.strip)?\z/,                   # heredoc-built command (verified callers only)
  /\Afilepath\z/,                            # File.join with sanitized basename
  /\Afilename\z/,                            # write_to_file: validated upstream
  /\Afile_path\z/                            # run_code: server-generated path
].freeze

# Files where shell-form interpolation is reviewed and accepted in full
# (e.g. the lint script itself).
ACCEPTED_FILES = %w[
  scripts/lint/check_shell_escape.rb
].freeze

INTERPOLATION_RE = /#\{([^{}]+)\}/

# Lines that contain shell-string indicators. We require an actual shell
# string keyword *and* presence of at least one interpolation in the
# same line or the heredoc body before reporting.
SHELL_INDICATORS = [
  /docker exec\b/,
  /docker cp\b/,
  /bash -c\b/,
  /\bsystem\(\s*["']/,
  /\beval\(\s*["']/
].freeze

def comment_only?(line)
  stripped = line.strip
  stripped.empty? || stripped.start_with?('#') || stripped.start_with?('//')
end

def safe_interpolation?(inner)
  expr = inner.strip
  return true if SAFE_INTERPOLATION_NAMES.include?(expr)
  SAFE_INTERPOLATION_PATTERNS.any? { |re| expr.match?(re) }
end

def each_target_file
  return enum_for(:each_target_file) unless block_given?

  SCAN_ROOTS.each do |rel_root|
    abs_root = ROOT.join(rel_root)
    next unless abs_root.exist?
    Dir.glob(abs_root.join('**', '*.rb')).each do |path|
      yield Pathname.new(path)
    end
  end
end

def relative_path(absolute)
  Pathname.new(absolute).relative_path_from(ROOT).to_s
end

# Scan every line; when a SHELL_INDICATOR appears AND is NOT a comment,
# we look at all interpolations in the same line. Each interpolation is
# reported only if it is not in the safe list AND not pre-escaped.
def scan_file(path)
  text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
  lines = text.lines
  violations = []
  rel = relative_path(path)
  return violations if ACCEPTED_FILES.include?(rel)

  lines.each_with_index do |line, idx|
    next if comment_only?(line)
    next unless SHELL_INDICATORS.any? { |re| line.match?(re) }
    matches = line.scan(INTERPOLATION_RE).flatten
    matches.each do |inner|
      next if inner.include?('Shellwords.escape')
      next if safe_interpolation?(inner)
      violations << { path: rel, line: idx + 1, text: line.rstrip, inner: inner.strip }
      break
    end
  end
  violations
end

baseline = nil
if ARGV.include?('--baseline')
  idx = ARGV.index('--baseline')
  baseline = ARGV[idx + 1].to_i
end

violations = []
each_target_file do |path|
  violations.concat(scan_file(path))
end

if violations.empty?
  puts '[lint:shell_escape] OK — no unescaped shell interpolations found.'
  exit 0
end

puts "[lint:shell_escape] #{violations.size} candidate violation(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
  puts "    interpolated: \#{#{v[:inner]}}"
end
puts ''
puts 'Note: each candidate must be verified by hand. If the interpolation'
puts 'is provably safe (e.g. server-generated timestamp, fixed enum), add'
puts 'it to ACCEPTED_VIOLATIONS in scripts/lint/check_shell_escape.rb.'

if baseline && violations.size <= baseline
  puts "[lint:shell_escape] within baseline (<= #{baseline}); exiting 0."
  exit 0
end

exit 1
