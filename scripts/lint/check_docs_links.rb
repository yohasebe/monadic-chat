#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'set'

ROOT = Pathname.new(__dir__).join('..', '..').realpath
DOCS_DIRS = [ROOT.join('docs'), ROOT.join('docs_dev')]

# Extract markdown links: [text](url)
LINK_PATTERN = /\[([^\]]+)\]\(([^)]+)\)/

violations = []
checked_files = Set.new

def external_link?(url)
  url.start_with?('http://', 'https://', 'mailto:', 'ftp://') ||
    url.match?(/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)
end

def anchor_only?(url)
  url.start_with?('#')
end

def sample_link?(url)
  # Skip documentation sample links that contain 'sample' keyword
  # or common placeholder patterns
  url_lower = url.downcase
  url_lower.include?('sample') ||
    url_lower == 'url' ||
    url_lower.include?('your-pattern-here') ||
    url_lower.include?('path/to/')
end

def inside_inline_code?(line, match_start)
  # Check if the match position is inside inline code (backticks)
  # Count backticks before the match position
  before_match = line[0...match_start]
  backtick_count = before_match.count('`')
  # If odd number of backticks, we're inside inline code
  backtick_count.odd?
end

def resolve_link_path(current_file, link_url, docs_root)
  # Remove docsify-specific size notation (e.g., ':size=40')
  link_url = link_url.split(/\s+/).first

  # Remove anchor fragments
  url_without_anchor = link_url.split('#').first
  return nil if url_without_anchor.nil? || url_without_anchor.empty?

  if url_without_anchor.start_with?('/')
    # Absolute path from docs root
    # /file.md or /ja/file.md
    target = docs_root.join(url_without_anchor.delete_prefix('/'))
  else
    # Relative path from current file's directory
    current_dir = current_file.dirname
    target = current_dir.join(url_without_anchor)
  end

  # Normalize the path
  target = target.cleanpath

  # If target is a directory, check for README.md
  if target.directory?
    target = target.join('README.md')
  elsif target.to_s.end_with?('/')
    # Link ends with /, treat as directory
    target = Pathname.new(target.to_s.chomp('/')).join('README.md')
  elsif !target.exist? && !target.to_s.end_with?('.md')
    # Try adding .md extension if file doesn't exist
    md_target = Pathname.new(target.to_s + '.md')
    target = md_target if md_target.exist?
  end

  target
end

DOCS_DIRS.each do |docs_root|
  next unless docs_root.exist?

  Dir.glob(docs_root.join('**', '*.md')).each do |file_path|
    current_file = Pathname.new(file_path)
    checked_files << current_file

    # Track if we're inside a code block
    in_code_block = false

    File.readlines(file_path).each_with_index do |line, idx|
      # Toggle code block state
      in_code_block = !in_code_block if line.strip.start_with?('```')

      # Skip lines inside code blocks
      next if in_code_block

      # Use scan with block to get match positions
      line.to_enum(:scan, LINK_PATTERN).each do
        match_data = Regexp.last_match
        text = match_data[1]
        url = match_data[2]
        match_start = match_data.begin(0)

        # Skip links inside inline code (backticks)
        next if inside_inline_code?(line, match_start)

        # Skip external links, anchor-only links, and sample links
        next if external_link?(url) || anchor_only?(url) || sample_link?(url)

        target_path = resolve_link_path(current_file, url, docs_root)
        next unless target_path

        unless target_path.exist?
          relative_current = current_file.relative_path_from(ROOT)
          relative_target = begin
            target_path.relative_path_from(ROOT)
          rescue ArgumentError
            target_path
          end

          violations << {
            file: relative_current,
            line: idx + 1,
            link_text: text,
            link_url: url,
            resolved_path: relative_target,
            message: "Link target does not exist"
          }
        end
      end
    end
  end
end

if violations.empty?
  puts "[lint] All documentation links are valid (checked #{checked_files.size} files)."
  exit 0
end

puts "[lint] Documentation link errors detected:"
puts
violations.each do |v|
  puts "  #{v[:file]}:#{v[:line]}"
  puts "    Link: [#{v[:link_text]}](#{v[:link_url]})"
  puts "    Resolved to: #{v[:resolved_path]}"
  puts "    Error: #{v[:message]}"
  puts
end

puts "Total: #{violations.size} broken link(s) found."
puts "Please fix or remove these links."
exit 1
