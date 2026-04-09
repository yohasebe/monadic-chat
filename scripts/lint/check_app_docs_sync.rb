#!/usr/bin/env ruby
# frozen_string_literal: true

# App-Docs Synchronization Checker
#
# Validates that the provider-app availability table in docs/basic-usage/basic-apps.md
# matches the actual MDSL files on disk. Detects:
#   - Apps in docs but not in MDSL (stale entries)
#   - Apps in MDSL but not in docs (missing entries)
#   - Provider mismatches (wrong checkmarks)
#
# Usage:
#   ruby scripts/lint/check_app_docs_sync.rb
#   npm run lint:app-docs-sync

require "pathname"

ROOT    = Pathname.new(__dir__).join("..", "..").realpath
APPS_DIR = ROOT.join("docker", "services", "ruby", "apps")
DOCS_EN  = ROOT.join("docs", "basic-usage", "basic-apps.md")

PROVIDER_SUFFIXES = {
  "openai" => "OpenAI",
  "claude" => "Claude",
  "cohere" => "Cohere",
  "deepseek" => "DeepSeek",
  "gemini" => "Google Gemini",
  "gemini3_preview" => "Google Gemini",
  "grok" => "xAI Grok",
  "mistral" => "Mistral",
  "perplexity" => "Perplexity",
  "ollama" => "Ollama"
}.freeze

PROVIDER_COLUMNS = [
  "OpenAI", "Claude", "Cohere", "DeepSeek",
  "Google Gemini", "xAI Grok", "Mistral", "Perplexity", "Ollama"
].freeze

# ---------------------------------------------------------------------------
# Build actual state from MDSL files
# ---------------------------------------------------------------------------
def scan_mdsl_files
  result = {} # { display_name => Set[provider_display_name] }

  Dir[APPS_DIR.join("*", "*.mdsl")].each do |path|
    content = File.read(path)

    # Skip disabled apps
    next if content.include?("disabled true")

    dirname = File.basename(File.dirname(path))
    filename = File.basename(path, ".mdsl")
    suffix = filename.sub("#{dirname}_", "")

    # Resolve provider
    provider_display = PROVIDER_SUFFIXES[suffix]
    next unless provider_display

    # Extract display_name
    display_name = nil
    content.each_line do |line|
      if line =~ /display_name\s+"([^"]+)"/
        display_name = $1
        break
      end
    end
    display_name ||= dirname.split("_").map(&:capitalize).join(" ")

    result[display_name] ||= Set.new
    result[display_name] << provider_display
  end

  # Special: Wikipedia (app.mdsl, no provider suffix)
  wiki_path = APPS_DIR.join("wikipedia", "wikipedia.mdsl")
  if wiki_path.exist?
    content = File.read(wiki_path)
    unless content.include?("disabled true")
      result["Wikipedia"] ||= Set.new
      result["Wikipedia"] << "OpenAI"
    end
  end

  result
end

# ---------------------------------------------------------------------------
# Parse docs table
# ---------------------------------------------------------------------------
def parse_docs_table(path)
  result = {} # { app_name => Set[provider_display_name] }
  lines = File.readlines(path)

  # Find table header
  header_idx = lines.index { |l| l.include?("| App") || l.include?("| アプリ") }
  return result unless header_idx

  header = lines[header_idx]
  columns = header.split("|").map(&:strip).reject(&:empty?)
  # columns[0] = "App", columns[1..] = provider names

  # Skip separator line
  data_start = header_idx + 2

  lines[data_start..].each do |line|
    break unless line.strip.start_with?("|")
    cells = line.split("|").map(&:strip).reject(&:empty?)
    next if cells.empty?

    app_name = cells[0]
    cells[1..].each_with_index do |cell, idx|
      if cell.include?("✅") && idx < columns.length - 1
        provider = columns[idx + 1]
        result[app_name] ||= Set.new
        result[app_name] << provider
      end
    end
  end

  result
end

# ---------------------------------------------------------------------------
# Compare
# ---------------------------------------------------------------------------
puts "App-Docs Synchronization Check"
puts "=" * 60

actual = scan_mdsl_files
docs = parse_docs_table(DOCS_EN)

errors = []

# Check for apps in docs but not in MDSL
docs.each do |app, providers|
  unless actual.key?(app)
    errors << "STALE in docs: '#{app}' not found in MDSL files"
    next
  end
  providers.each do |p|
    unless actual[app].include?(p)
      errors << "STALE: #{app} / #{p} — in docs but no MDSL"
    end
  end
end

# Check for apps in MDSL but not in docs
actual.each do |app, providers|
  unless docs.key?(app)
    errors << "MISSING from docs: '#{app}' exists in MDSL but not in docs table"
    next
  end
  providers.each do |p|
    unless docs[app].include?(p)
      errors << "MISSING: #{app} / #{p} — MDSL exists but not in docs"
    end
  end
end

if errors.empty?
  puts "All #{actual.size} apps match between MDSL files and docs."
  exit 0
else
  puts "Found #{errors.size} discrepancy(ies):\n\n"
  errors.sort.each { |e| puts "  #{e}" }
  puts "\nUpdate docs/basic-usage/basic-apps.md to match actual MDSL files."
  exit 1
end
