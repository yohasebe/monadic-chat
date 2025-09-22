#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath
CONFIG_PATH = ROOT.join('config', 'deprecated_model_terms.txt')

unless CONFIG_PATH.exist?
  warn "[lint] Deprecated model terms config not found: #{CONFIG_PATH}"
  exit 1
end

TERMS = CONFIG_PATH.readlines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }

if TERMS.empty?
  puts '[lint] No deprecated model terms configured. Skipping check.'
  exit 0
end

TARGET_DIRS = %w[docs docs_dev translations]
ALLOWED_EXTENSIONS = %w[.md .markdown .json .yml .yaml .txt .js .ts .tsx]

violations = []

TARGET_DIRS.each do |dir|
  base = ROOT.join(dir)
  next unless base.exist?

  Dir.glob(base.join('**', '*'), File::FNM_DOTMATCH).each do |path|
    next unless File.file?(path)
    next unless ALLOWED_EXTENSIONS.include?(File.extname(path))

    relative_path = Pathname.new(path).relative_path_from(ROOT)
    File.readlines(path).each_with_index do |line, idx|
      TERMS.each do |term|
        if line.downcase.include?(term)
          violations << {
            file: relative_path,
            line: idx + 1,
            term: term,
            snippet: line.strip
          }
          break
        end
      end
    end
  end
end

if violations.empty?
  puts '[lint] No deprecated model terms found.'
  exit 0
end

puts '[lint] Deprecated model terms detected:'
violations.each do |v|
  puts "  #{v[:file]}:#{v[:line]} contains '#{v[:term]}'"
  puts "    #{v[:snippet]}" unless v[:snippet].empty?
end

puts '\nUpdate documentation/translations to remove or replace deprecated model names.'
exit 1
