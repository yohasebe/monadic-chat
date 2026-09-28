#!/usr/bin/env ruby
# frozen_string_literal: true

# API credentials belong in headers, never in URL query strings. Ripper keeps
# comments, regexp matchers and ordinary keyword arguments out of this check.
# Inspect string fragments too, so interpolation, concatenation and encoded
# key expressions cannot hide the query parameter from the rule.
require 'pathname'
require 'ripper'

root = Pathname.new(__dir__).join('../..').realpath
scan_roots = %w[docker/services/ruby/lib docker/services/ruby/scripts docker/services/ruby/apps]
violations = []
scan_roots.each do |dir|
  root.join(dir).glob('**/*.rb').each do |path|
    tokens = Ripper.lex(path.read)
    in_regexp = false
    tokens.each_with_index do |(position, type, value, _state), index|
      in_regexp = true if type == :on_regexp_beg
      in_regexp = false if type == :on_regexp_end
      next if in_regexp
      next unless type == :on_tstring_content
      # ?key= and &key= are forbidden even for literal values. Also catch a
      # separately constructed key= fragment followed by key interpolation.
      query_key = value.match?(/[?&](?:key|api_key)=/i)
      fragment_key = value.match?(/\b(?:key|api_key)=\z/i) &&
                     tokens[index + 1]&.[](1) == :on_embexpr_beg &&
                     tokens[(index + 2)..].take_while { |token| token[1] != :on_embexpr_end }
                           .any? { |token| token[2].match?(/api_key/i) }
      next unless query_key || fragment_key

      violations << [path.relative_path_from(root).to_s, position.first]
    end
  end
end
violations.uniq!
puts "[lint:api_key_urls] #{violations.size} violation(s)"
# Never print source snippets: a violation might itself contain a credential.
violations.each { |path, line| puts "  #{path}:#{line}" }
exit(violations.empty? ? 0 : 1)
