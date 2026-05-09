#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: bare `ws.send(...)` callsites outside the
# central `monadic-ws.js` helper.
#
# Catches the failure mode that motivated H7: callers reach directly
# for the module-scope WebSocket and crash with a null deref when the
# socket is mid-reconnect, with no consistent fallback (queue, alert,
# or fail-fast). The canonical replacement is `window.safeWsSend(...)`,
# which centralises null/CONNECTING/CLOSED handling, the
# reconnect-and-replay queue, and idempotency classification.
#
# What we flag:
#   - `ws.send(...)` or `window.ws.send(...)` in the frontend JS tree,
#     except inside the helper file itself.
#
# What we DO NOT flag:
#   - mock setup like `global.ws = { send: jest.fn() }` (no parens
#     immediately after `.send`).
#   - assertions like `expect(ws.send).toHaveBeenCalled(...)` (the
#     parens belong to the matcher, not to `.send`).
#   - bundle / minified outputs (skipped by extension filter).
#   - comments (`//` and `/* */` lines are skipped).
#
# Output mode:
#   Same exit-code semantics as the other lint scripts.

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

SCAN_ROOTS = [
  'docker/services/ruby/public/js'
].freeze

ALLOWED_EXTENSIONS = %w[.js .mjs].freeze

# Files where the literal call is canonical (the helper itself is the
# sole place that should ever invoke `ws.send` directly) or where the
# scanner needs to read the regex string itself. Tracked explicitly so
# any new occurrence has to be defended on review rather than silently
# slipping through.
ACCEPTED_FILES = %w[
  docker/services/ruby/public/js/monadic/monadic-ws.js
].freeze

# Word-boundary anchor avoids matching identifiers that merely contain
# "ws" (e.g. `mockws.send`, `localWs.send`, `_ws.send`). The `(window\.)?`
# prefix catches both the bare and namespaced forms. We require an
# opening paren after `.send` so property access (assertions / spies
# in tests) is not flagged.
PATH_RE = /\b(?:window\.)?ws\.send\s*\(/

def each_target_file
  return enum_for(:each_target_file) unless block_given?
  SCAN_ROOTS.each do |rel_root|
    abs_root = ROOT.join(rel_root)
    next unless abs_root.exist?
    Dir.glob(abs_root.join('**', '*')).each do |path|
      next unless File.file?(path)
      next unless ALLOWED_EXTENSIONS.include?(File.extname(path))
      # Skip generated bundles — these are emitted by build_js_bundle.mjs
      # and inevitably contain the helper's internal sends inlined.
      next if path.include?('.bundle.')
      next if path.include?('.min.')
      yield Pathname.new(path)
    end
  end
end

def relative_path(absolute)
  Pathname.new(absolute).relative_path_from(ROOT).to_s
end

baseline = nil
if ARGV.include?('--baseline')
  idx = ARGV.index('--baseline')
  baseline = ARGV[idx + 1].to_i
end

violations = []
each_target_file do |path|
  rel = relative_path(path)
  next if ACCEPTED_FILES.include?(rel)
  text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
  in_block_comment = false
  text.each_line.with_index do |line, idx|
    stripped = line.strip
    # Track /* ... */ block comments across lines. A line that opens
    # AND closes a block on its own resets correctly because we test
    # `start` before flipping for `end`.
    if in_block_comment
      in_block_comment = false if stripped.include?('*/')
      next
    end
    if stripped.start_with?('/*') && !stripped.include?('*/')
      in_block_comment = true
      next
    end
    next if stripped.start_with?('//') || stripped.start_with?('*')
    next unless line.match?(PATH_RE)
    violations << { path: rel, line: idx + 1, text: line.rstrip }
  end
end

if violations.empty?
  puts '[lint:bare_ws_send] OK — no bare ws.send() callsites outside the monadic-ws.js helper.'
  exit 0
end

puts "[lint:bare_ws_send] #{violations.size} violation(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
end
puts ''
puts 'Migration target: window.safeWsSend(payload, opts)'
puts '(see docs_dev/safe_ws_send_plan.md §3 for the helper API and'
puts 'idempotency contract).'

if baseline && violations.size <= baseline
  puts "[lint:bare_ws_send] within baseline (<= #{baseline}); exiting 0."
  exit 0
end

exit 1
