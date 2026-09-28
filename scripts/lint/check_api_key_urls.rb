#!/usr/bin/env ruby
# frozen_string_literal: true

# API credentials belong in headers, never in URL query strings.
#
# Scope: Ruby, JavaScript and Python sources under RUBY_ROOTS and SCRIPT_GLOBS. Ruby is read with Ripper, which keeps
# comments, regexp matchers and keyword arguments out of the check. JavaScript
# and Python are read line by line with comments stripped, which is coarser:
# a query key assembled across several lines, or through a helper that builds
# the query from a hash, is not caught there. The runtime invariant specs
# (spec/unit/utils/gemini_key_header_spec.rb) cover the requests themselves.
#
# Forms caught in every language:
#   "...?key=..." / "...&api_key=..."          a query key written into a literal
#   "key=#{api_key}" / `key=${apiKey}` / f"key={api_key}"   interpolated
#   "...&" + "key=" + api_key                   concatenated onto a literal
require 'pathname'
require 'ripper'

root = Pathname.new(__dir__).join('../..').realpath
RUBY_ROOTS = %w[docker/services/ruby/lib docker/services/ruby/scripts docker/services/ruby/apps].freeze
SCRIPT_GLOBS = %w[
  app/**/*.js scripts/**/*.js scripts/**/*.mjs
  docker/services/ruby/public/js/**/*.js
  docker/services/**/*.py
].freeze
# Third-party and generated code is not ours to police here.
SCRIPT_EXCLUDE = %r{/(vendor|node_modules|dist|\.venv|site-packages)/|\.min\.js\z|\.bundle\.}

QUERY_KEY = /[?&](?:key|api_key)=/i
KEY_FRAGMENT_END = /\b(?:key|api_key)=\z/i
CREDENTIAL_NAME = /api_?key|apikey|token|secret/i
# A scan that reads nothing also reports zero violations. These floors sit a
# little below the current counts (Ruby 279, JavaScript 107, Python 27) so a
# misresolved root or a broken glob fails loudly; lower them when files are
# genuinely removed.
MIN_SCANNED = { ruby: 250, javascript: 95, python: 24 }.freeze

violations = []
scanned = Hash.new(0)

# --- Ruby ------------------------------------------------------------------
def next_significant(tokens, index)
  tokens[(index + 1)..].find { |token| !%i[on_sp on_ignored_nl on_nl].include?(token[1]) }
end

RUBY_ROOTS.each do |dir|
  root.join(dir).glob('**/*.rb').each do |path|
    scanned[:ruby] += 1
    tokens = Ripper.lex(path.read)
    in_regexp = false
    tokens.each_with_index do |(position, type, value, _state), index|
      in_regexp = true if type == :on_regexp_beg
      in_regexp = false if type == :on_regexp_end
      next if in_regexp
      next unless type == :on_tstring_content

      # ?key= and &key= are forbidden even for literal values.
      query_key = value.match?(QUERY_KEY)
      # A key= fragment followed by interpolation of a credential.
      interpolated = value.match?(KEY_FRAGMENT_END) &&
                     tokens[index + 1]&.[](1) == :on_embexpr_beg &&
                     tokens[(index + 2)..].take_while { |token| token[1] != :on_embexpr_end }
                           .any? { |token| token[2].match?(CREDENTIAL_NAME) }
      # A key= fragment that ends its literal and is then joined with `+`:
      # "...&" + "key=" + api_key splits the query across literals.
      concatenated = value.match?(KEY_FRAGMENT_END) &&
                     tokens[index + 1]&.[](1) == :on_tstring_end &&
                     next_significant(tokens, index + 1)&.values_at(1, 2) == [:on_op, '+']
      next unless query_key || interpolated || concatenated

      violations << [path.relative_path_from(root).to_s, position.first]
    end
  end
end

# --- JavaScript and Python ---------------------------------------------------
# A key= that ends a string literal and is followed by `+`, or that is
# followed by template / f-string interpolation of a credential.
JS_PY_PATTERNS = [
  QUERY_KEY,
  /\b(?:key|api_key)=["'`]\s*\+/i,                                  # "key=" + x
  /\b(?:key|api_key)=\$\{[^}]*(?:api_?key|apikey|token|secret)[^}]*\}/i, # `key=${apiKey}`
  /\b(?:key|api_key)=\{[^}]*(?:api_?key|apikey|token|secret)[^}]*\}/i     # f"key={api_key}"
].freeze

def strip_comment(line, python)
  stripped = line.lstrip
  return '' if stripped.start_with?(python ? '#' : '//') || stripped.start_with?('*', '/*')

  line
end

SCRIPT_GLOBS.flat_map { |glob| root.glob(glob) }.uniq.each do |path|
  rel = path.relative_path_from(root).to_s
  next if "/#{rel}".match?(SCRIPT_EXCLUDE)

  python = rel.end_with?('.py')
  scanned[python ? :python : :javascript] += 1
  path.each_line.with_index(1) do |line, number|
    code = strip_comment(line, python)
    next if code.empty?
    next unless JS_PY_PATTERNS.any? { |pattern| code.match?(pattern) }

    violations << [rel, number]
  end
end

violations.uniq!
short = MIN_SCANNED.select { |lang, floor| scanned[lang] < floor }
puts "[lint:api_key_urls] scanned #{MIN_SCANNED.keys.map { |lang| "#{lang} #{scanned[lang]}" }.join(', ')}"
short.each { |lang, floor| puts "  #{lang}: scanned #{scanned[lang]} file(s), expected at least #{floor}" }
puts "[lint:api_key_urls] #{violations.size} violation(s)"
# Never print source snippets: a violation might itself contain a credential.
violations.each { |path, line| puts "  #{path}:#{line}" }
exit(violations.empty? && short.empty? ? 0 : 1)
