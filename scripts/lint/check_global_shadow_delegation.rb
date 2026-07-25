#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: top-level same-name delegation wrappers in classic
# (non-module) scripts.
#
# Catches the failure mode found in the 2026-07-25 dogfood: a top-level
#
#   function escapeHtml(text) {
#     return window.escapeHtml(text);
#   }
#
# in a classic script REPLACES window.escapeHtml with itself, because
# top-level function declarations (and `var` bindings) in classic scripts
# are properties of window. The body then calls itself — infinite
# recursion, RangeError: Maximum call stack size exceeded.
#
# Why Jest cannot catch this: Jest wraps each file in CommonJS, so
# top-level declarations never attach to window/globalThis. Only the
# real (browser/webview) runtime exhibits the shadowing.
#
# What we flag (top-level = column 0 only; indented wrappers inside
# IIFEs/closures do NOT attach to window and are safe):
#   - `function NAME(...) { return window.NAME(...); }`
#   - `var NAME = function (...) { return window.NAME(...); }`
# (`const`/`let` at top level never attach to window, so arrow-function
# wrappers are not flagged.)
#
# Remediation: call `window.NAME(...)` directly at the call sites, or
# rename the wrapper so it cannot shadow the global.
#
# Output mode: same exit-code semantics as the other lint scripts.

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

SCAN_ROOTS = [
  'docker/services/ruby/public/js'
].freeze

ALLOWED_EXTENSIONS = %w[.js .mjs].freeze

# Top-level function declaration whose body delegates to the same-named
# window property. `^` anchors at column 0 (multiline) so nested
# wrappers are ignored.
FUNCTION_DELEGATION_RE = /^function\s+(\w+)\s*\([^)]*\)\s*\{\s*return\s+window\.\1\s*\(/

# Top-level `var` binding of a function expression that delegates to the
# same-named window property. `var` attaches to window; `const`/`let`
# do not, so only `var` is matched here.
VAR_DELEGATION_RE = /^var\s+(\w+)\s*=\s*function\s*\([^)]*\)\s*\{\s*return\s+window\.\1\s*\(/

def each_target_file
  return enum_for(:each_target_file) unless block_given?
  SCAN_ROOTS.each do |rel_root|
    abs_root = ROOT.join(rel_root)
    next unless abs_root.exist?
    Dir.glob(abs_root.join('**', '*')).each do |path|
      next unless File.file?(path)
      next unless ALLOWED_EXTENSIONS.include?(File.extname(path))
      # Skip generated bundles/minified outputs.
      next if path.include?('.bundle.')
      next if path.include?('.min.')
      yield Pathname.new(path)
    end
  end
end

def relative_path(absolute)
  Pathname.new(absolute).relative_path_from(ROOT).to_s
end

violations = []
each_target_file do |path|
  rel = relative_path(path)
  text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
  # The pattern spans multiple lines (declaration line + body line), so
  # scan the whole file text and derive line numbers from match offsets.
  [FUNCTION_DELEGATION_RE, VAR_DELEGATION_RE].each do |re|
    text.scan(re) do
      m = Regexp.last_match
      line_no = text[0...m.begin(0)].count("\n") + 1
      violations << { path: rel, line: line_no, text: m[0].lines.first.rstrip }
    end
  end
end

if violations.empty?
  puts '[lint:global_shadow_delegation] OK — no top-level same-name window-delegation wrappers.'
  exit 0
end

puts "[lint:global_shadow_delegation] #{violations.size} violation(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
end
puts ''
puts 'In classic scripts, a top-level function/var declaration IS a window'
puts 'property: the wrapper overwrites the global it delegates to and'
puts 'recurses infinitely. Jest (CommonJS-wrapped) cannot detect this.'
puts 'Remediation: call window.NAME(...) directly at the call sites, or'
puts 'rename the wrapper so it cannot shadow the global.'

exit 1
