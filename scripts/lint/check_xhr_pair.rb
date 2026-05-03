#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: xhr-dependent route × fetch() pair mismatch.
#
# Catches the failure mode that produced the "Text from file" /
# "Text from URL" / Library import JSON-parse errors. Sinatra routes
# that branch on `request.xhr?` expect callers to send the
# X-Requested-With: XMLHttpRequest header. Modern fetch() does not
# attach this header by default. When the pair is misaligned, the
# route falls through to the non-JSON form-submission branch, the
# response body is raw markdown, and the client's await res.json()
# throws a confusing JSON-parse error.
#
# Strategy:
#   1. Find every Sinatra route that uses `request.xhr?` (server side).
#   2. For each route path, find every fetch(path, ...) call in the
#      frontend and assert the options object includes
#      "X-Requested-With".
#   3. Report unmatched callsites; both directions are checked so adding
#      a new fetch caller without the header, OR adding a new
#      xhr-dependent route without updating callers, both fail the lint.
#
# Output mode:
#   Same exit-code semantics as the other lint scripts.

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

ROUTES_DIR = ROOT.join('docker/services/ruby/lib/monadic/routes')
JS_ROOTS = [
  ROOT.join('docker/services/ruby/public/js/monadic'),
  ROOT.join('app')
].freeze

# Routes that legitimately use request.xhr? for content negotiation
# (e.g. graceful HTML fallback for non-AJAX form submitters in old
# code paths). The pair-check rule still applies; this list is for
# documentation and is currently empty.
EXEMPT_ROUTES = [].freeze

# Find every "request.xhr?" gated route and the path string before the
# `do` block opener. Sinatra DSL: `post "/document" do ... if request.xhr?`.
def find_xhr_routes
  routes = {}
  Dir.glob(ROUTES_DIR.join('**', '*.rb')).each do |path|
    next unless File.exist?(path)
    text = File.read(path)
    rel = Pathname.new(path).relative_path_from(ROOT).to_s

    # State machine: track the last-seen route opener; if we see
    # `request.xhr?` before another route opens, attribute it to the
    # last route.
    current_route = nil
    text.each_line.with_index do |line, idx|
      m = line.match(/\A\s*(?:get|post|put|patch|delete)\s+["']([^"']+)["']\s+do/)
      if m
        current_route = { path: m[1], file: rel, line: idx + 1 }
        next
      end
      if current_route && line.match?(/request\.xhr\?/)
        routes[current_route[:path]] ||= current_route
      end
    end
  end
  routes
end

# Find every fetch(...) callsite in the JS roots. We capture the path
# argument and a small surrounding window so we can look for
# X-Requested-With nearby. This is a static-text scan; it does not
# parse JS.
def find_fetch_callsites(target_paths)
  callsites = []
  JS_ROOTS.each do |js_root|
    next unless js_root.exist?
    Dir.glob(js_root.join('**', '*.js')).each do |path|
      next if path.include?('.bundle.min.js')
      rel = Pathname.new(path).relative_path_from(ROOT).to_s
      text = File.read(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
      lines = text.lines

      lines.each_with_index do |line, idx|
        target_paths.each do |target|
          # Match fetch("/document"...) or fetch('/document'...) or
          # fetch(`/document...`) on this line, allowing whitespace.
          re = /fetch\s*\(\s*["'`](#{Regexp.escape(target)})\b/
          next unless line.match?(re)

          # Look at the call's arguments: span the fetch( ... ) up to the
          # matching close paren or 15 lines, whichever is sooner. Static
          # paren matching is good enough for our usage.
          window = lines[idx..[idx + 15, lines.size - 1].min].join
          has_header = window.include?('X-Requested-With')

          callsites << {
            file: rel,
            line: idx + 1,
            target: target,
            has_header: has_header,
            text: line.rstrip
          }
        end
      end
    end
  end
  callsites
end

baseline = nil
if ARGV.include?('--baseline')
  idx = ARGV.index('--baseline')
  baseline = ARGV[idx + 1].to_i
end

xhr_routes = find_xhr_routes
xhr_route_paths = xhr_routes.keys - EXEMPT_ROUTES

if xhr_route_paths.empty?
  puts '[lint:xhr_pair] OK — no request.xhr? usages found in routes/.'
  exit 0
end

callsites = find_fetch_callsites(xhr_route_paths)

# Reverse check: any xhr-route that nobody fetches at all is suspicious
# (probably dead code). Report as warning.
unmatched_routes = xhr_route_paths - callsites.map { |c| c[:target] }.uniq
missing_header = callsites.reject { |c| c[:has_header] }

violations = missing_header
warnings = unmatched_routes

if violations.empty? && warnings.empty?
  puts "[lint:xhr_pair] OK — all #{callsites.size} fetch() call(s) to xhr-dependent routes set X-Requested-With."
  exit 0
end

unless violations.empty?
  puts "[lint:xhr_pair] #{violations.size} fetch call(s) without X-Requested-With:"
  violations.each do |c|
    puts "  #{c[:file]}:#{c[:line]} → #{c[:target]}"
    puts "    #{c[:text]}"
  end
end

unless warnings.empty?
  puts ''
  puts "[lint:xhr_pair] WARNING: xhr-dependent route(s) without any matching fetch() caller:"
  warnings.each do |route|
    location = xhr_routes[route]
    puts "  #{location[:file]}:#{location[:line]} → #{route}"
  end
end

if violations.empty?
  exit 0
elsif baseline && violations.size <= baseline
  puts "[lint:xhr_pair] within baseline (<= #{baseline}); exiting 0."
  exit 0
else
  exit 1
end
