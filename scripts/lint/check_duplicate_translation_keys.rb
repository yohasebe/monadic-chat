#!/usr/bin/env ruby
# frozen_string_literal: true

# Duplicate Translation Key Checker
#
# Scans translations.js for duplicate keys within the same object scope.
# JavaScript silently accepts duplicate keys (the last one wins), so this
# check catches merge/refactor accidents where two definitions of the same
# key linger at the same scope level.
#
# Detection strategy:
#   - Track scope stack based on curly-brace nesting
#   - Within each scope, collect all keys defined at that level
#   - Flag any key name that appears more than once in the same scope
#
# Usage:
#   ruby scripts/lint/check_duplicate_translation_keys.rb
#   npm run test:translations-duplicates

require "pathname"

ROOT = Pathname.new(__dir__).join("..", "..").realpath
TARGET = ROOT.join("docker", "services", "ruby", "public", "js", "i18n", "translations.js")

KEY_LINE = /\A\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/.freeze

def scan_duplicates(path)
  scope_stack = [{ name: "(root)", keys: {}, start_line: 1 }]
  duplicates = []

  path.each_line.with_index(1) do |line, lineno|
    # Strip string contents so braces inside strings aren't counted.
    # Simple handling: drop anything between matched quotes.
    stripped = line.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'(?:\\.|[^'\\])*'/, "''")

    # Record keys at the current scope before processing braces on this line
    if (match = line.match(KEY_LINE))
      key = match[1]
      # Only treat as a property key if a colon follows the identifier at
      # object-literal position (not inside an expression). The KEY_LINE
      # regex anchors at indent + identifier + colon, which is accurate
      # enough for this hand-written object literal format.
      current = scope_stack.last
      if current[:keys].key?(key)
        duplicates << {
          key: key,
          first_line: current[:keys][key],
          duplicate_line: lineno,
          scope_name: current[:name],
          scope_start: current[:start_line]
        }
      else
        current[:keys][key] = lineno
      end
    end

    # Adjust scope stack based on braces on this line (after key collection).
    opens = stripped.count("{")
    closes = stripped.count("}")

    opens.times do
      # The key that introduced this new scope is the most recent one
      # we saw on this line (if any).
      last_key = line.match(KEY_LINE)&.[](1) || "(anonymous)"
      scope_stack.push({ name: last_key, keys: {}, start_line: lineno })
    end
    closes.times do
      scope_stack.pop if scope_stack.size > 1
    end
  end

  duplicates
end

unless TARGET.exist?
  warn "ERROR: target file not found: #{TARGET}"
  exit 1
end

puts "Translation Duplicate Key Check"
puts "=" * 60
puts "Target: #{TARGET.relative_path_from(ROOT)}"
puts

duplicates = scan_duplicates(TARGET)

if duplicates.empty?
  puts "No duplicate keys found."
  exit 0
end

puts "Found #{duplicates.size} duplicate key(s):"
puts
duplicates.each do |dup|
  puts "  #{dup[:key]} (in scope '#{dup[:scope_name]}' opened at L#{dup[:scope_start]})"
  puts "    first:      line #{dup[:first_line]}"
  puts "    duplicate:  line #{dup[:duplicate_line]}"
  puts
end
puts "JavaScript silently keeps only the last definition. Please remove"
puts "one of each pair so the effective value is explicit."
exit 1
