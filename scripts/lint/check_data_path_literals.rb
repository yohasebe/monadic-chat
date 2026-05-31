#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: bare "/monadic/data" string literals outside the
# Environment helper.
#
# Catches the failure mode where a new file builds its own dual-mode
# path resolution by hand and gets the dev-mode branch wrong (cf.
# jupyter_helper.rb hard-coding "/Users/yohasebe/monadic/data"). The
# canonical replacement is Monadic::Utils::Environment.data_path
# (alias: shared_volume), which already handles in_container? branching
# uniformly across Ruby. The SHARED_VOL / LOCAL_SHARED_VOL constants
# defined in app.rb are also acceptable.
#
# What we flag:
#   - "/monadic/data" or '/monadic/data' literals in lib/scripts/apps,
#     except inside the Environment helper itself and a small allow-list.
#
# What we DO NOT flag:
#   - the constant definitions in app.rb (SHARED_VOL = "/monadic/data")
#   - the Environment helper that resolves the value
#   - public docs / docs_dev (these are documentation)
#   - test/spec files
#
# Output mode:
#   Same exit-code semantics as the other lint scripts.

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

SCAN_ROOTS = [
  'app',
  'docker/services/ruby/lib',
  'docker/services/ruby/scripts',
  'docker/services/ruby/apps',
  'docker/services/ruby/public/js'
].freeze

ALLOWED_EXTENSIONS = %w[.rb .js .mjs .erb .mdsl].freeze

# Files where the literal is the canonical definition or has been
# audited as legitimate (Sinatra HTTP route, dual-mode fallback array,
# guard check, container-view path inside docker exec). Tracked
# explicitly so any new occurrence has to be defended on review rather
# than silently slipping through. The list is the audit baseline; new
# files added here are deliberate "deprecate, migrate later" entries.
ACCEPTED_FILES = %w[
  app/main.js
  scripts/lint/check_data_path_literals.rb
  docker/services/ruby/lib/monadic/utils/environment.rb
  docker/services/ruby/lib/monadic/shell.rb
  docker/services/ruby/lib/monadic/app.rb
  docker/services/ruby/lib/monadic/extractor/endpoint.rb
  docker/services/ruby/lib/monadic/embeddings/endpoint.rb
  docker/services/ruby/lib/monadic/library/file_importer.rb
  docker/services/ruby/lib/monadic/shared_tools/file_operations.rb
  docker/services/ruby/lib/monadic/adapters/read_write_helper.rb
  docker/services/ruby/lib/monadic/adapters/jupyter_helper.rb
  docker/services/ruby/lib/monadic/adapters/latex_helper.rb
  docker/services/ruby/lib/monadic/adapters/vendors/grok_helper.rb
  docker/services/ruby/apps/auto_forge/auto_forge_debugger.rb
  docker/services/ruby/lib/monadic/agents/video_analyze_agent.rb
  docker/services/ruby/lib/monadic/adapters/selenium_helper.rb
  docker/services/ruby/lib/monadic/adapters/vendors/gemini_helper.rb
  docker/services/ruby/lib/monadic/routes/static_routes.rb
  docker/services/ruby/scripts/cli_tools/tts_query.rb
  docker/services/ruby/scripts/generators/image_generator_grok.rb
  docker/services/ruby/scripts/generators/video_generator_gemini.rb
  docker/services/ruby/scripts/generators/video_generator_grok.rb
  docker/services/ruby/scripts/generators/video_generator_openai.rb
  docker/services/ruby/apps/music_lab/music_lab_tools.rb
  docker/services/ruby/apps/syntax_tree/syntax_tree_tools.rb
].freeze

PATH_RE = %r{['"]/monadic/data['"/]}

def each_target_file
  return enum_for(:each_target_file) unless block_given?
  SCAN_ROOTS.each do |rel_root|
    abs_root = ROOT.join(rel_root)
    next unless abs_root.exist?
    Dir.glob(abs_root.join('**', '*')).each do |path|
      next unless File.file?(path)
      next unless ALLOWED_EXTENSIONS.include?(File.extname(path))
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
  text.each_line.with_index do |line, idx|
    next if line.strip.start_with?('#') || line.strip.start_with?('//')
    next unless line.match?(PATH_RE)
    violations << { path: rel, line: idx + 1, text: line.rstrip }
  end
end

if violations.empty?
  puts '[lint:data_path_literals] OK — no bare "/monadic/data" literals outside the Environment helper.'
  exit 0
end

puts "[lint:data_path_literals] #{violations.size} violation(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
end
puts ''
puts 'Migration target: Monadic::Utils::Environment.data_path'
puts '(or .shared_volume for clarity in shell-context code).'

if baseline && violations.size <= baseline
  puts "[lint:data_path_literals] within baseline (<= #{baseline}); exiting 0."
  exit 0
end

exit 1
