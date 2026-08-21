#!/usr/bin/env ruby
# frozen_string_literal: true

# Anti-pattern lint: outbound `http` gem calls with no timeout.
#
# The http gem (httprb) has NO default timeout, unlike Net::HTTP's 60s. A peer
# that accepts the connection and then goes silent parks the calling thread
# forever — the observed failure mode elsewhere was a process spinning at 99%
# CPU for days, immune to SIGTERM.
#
# What we flag: a chain that starts at `HTTP.` and reaches a verb
# (`get`/`post`/`headers`/`follow`/...) without a `.timeout(` anywhere in the
# chain. Chains routinely span several lines:
#
#   http = HTTP.headers(headers)
#              .timeout(connect: 30, read: 120)   # <- covered, on a later line
#              .post(url, json: body)
#
# so the whole statement is examined, not a single line.
#
# Remediation: build the client through Monadic::Utils::HttpClient
# (`lib/monadic/utils/http_client.rb`), which picks per-operation timeouts by
# the shape of the wait — `rest`, `generation`, `streaming`, `download`.
# Two traps that helper exists to prevent:
#   - `HTTP.timeout(60)` (bare Numeric) is a GLOBAL cap on the whole request
#     and aborts healthy long streaming responses.
#   - omitting `write:` leaves it at the gem default of 0.25s, which breaks
#     large uploads (base64 images, PDFs, audio).

require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').realpath

SCAN_ROOTS = [
  'docker/services/ruby/lib',
  'docker/services/ruby/scripts',
  'docker/services/ruby/apps'
].freeze

ALLOWED_EXTENSIONS = %w[.rb].freeze

# Verbs that actually issue or configure a request off the HTTP constant.
HTTP_CALL_RE = /\bHTTP\.(headers|get|post|put|patch|delete|follow|via|auth|basic_auth|accept|persistent)\b/

# Collect the whole method chain starting at `idx`.
#
# Two earlier attempts got this wrong and both directions hurt:
#   - a fixed N-line lookahead swallowed a `.timeout(` from an unrelated
#     statement further down and cleared a real violation (false negative);
#   - "continue while the next line starts with a dot" stopped at a line
#     beginning with a closing bracket, which is exactly how a multi-line
#     argument list continues into the timeout call (false positive):
#
#       response = HTTP.headers(
#         "Authorization" => ...,
#         "Content-Type"  => ...
#       ).timeout(connect: ..., write: ..., read: ...)
#        .post(url, body: ...)
#
# So track bracket depth: while the statement still has an unclosed bracket we
# are inside it, and once it closes we keep going only for genuine chain
# continuation (leading dot, or a line left open by a trailing dot/comma/backslash).
def chain_text(lines, idx)
  text = +lines[idx].to_s
  depth = bracket_delta(lines[idx])
  j = idx
  while j + 1 < lines.length
    nxt = lines[j + 1]
    inside = depth > 0
    continues = inside ||
                nxt.lstrip.start_with?('.', ')', ']', '}') ||
                lines[j].rstrip.end_with?('.', ',', '\\')
    break unless continues
    text << nxt
    depth += bracket_delta(nxt)
    j += 1
  end
  text
end

# Net bracket balance of a line, ignoring brackets inside strings/comments well
# enough for this purpose.
def bracket_delta(line)
  code = line.sub(/#.*\z/, '')
  code = code.gsub(/"(?:[^"\\]|\\.)*"/, '""').gsub(/'(?:[^'\\]|\\.)*'/, "''")
  code.count('([{') - code.count(')]}')
end

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

# Helpers that take a client and apply the caller's configured timeouts
# themselves (see BaseVendorHelper#post_json_with_retries).
TIMEOUT_APPLYING_HELPERS = %w[post_json_with_retries].freeze

# True when `line` binds the client to a local that is later given a timeout,
# or handed to a helper that applies one. Scans to the end of the enclosing
# method so a timeout applied at the point of use still counts.
def timed_out_downstream?(lines, idx, line)
  m = line.match(/^\s*(\w+)\s*=\s*.*HTTP\./)
  return false unless m

  var = Regexp.escape(m[1])
  rest = []
  ((idx + 1)...lines.length).each do |k|
    break if lines[k] =~ /^\s*(private\s+)?def\s/
    rest << lines[k]
  end
  body = rest.join

  return true if body =~ /\b#{var}\.timeout\(/
  TIMEOUT_APPLYING_HELPERS.any? { |h| body =~ /#{Regexp.escape(h)}\(\s*#{var}\b/ }
end

violations = []
each_target_file do |path|
  rel = relative_path(path)
  lines = File.readlines(path, encoding: 'UTF-8', invalid: :replace, undef: :replace, replace: '?')

  lines.each_with_index do |line, idx|
    next unless line =~ HTTP_CALL_RE
    # Already routed through the shared builder, or timed out on this line.
    next if line.include?('HttpClient')
    next if line.include?('timeout')
    # A `.timeout(` later in the *same* chain covers it.
    next if chain_text(lines, idx).include?('.timeout(')
    # The client is very often parked in a local first and timed out at the
    # point of use — `http = HTTP.headers(h)` … `http.timeout(...).post(...)`,
    # or handed to post_json_with_retries, which applies the vendor's own
    # configured timeouts. Both are covered; only flag a binding whose value
    # is never given one.
    next if timed_out_downstream?(lines, idx, line)

    violations << { path: rel, line: idx + 1, text: line.strip[0, 100] }
  end
end

if violations.empty?
  puts '[lint:http_timeout] OK — no untimed HTTP calls.'
  exit 0
end

puts "[lint:http_timeout] #{violations.size} untimed HTTP call(s):"
violations.each do |v|
  puts "  #{v[:path]}:#{v[:line]}: #{v[:text]}"
end
puts ''
puts 'The http gem has no default timeout: a silent peer parks the calling'
puts 'thread forever. Build the client through Monadic::Utils::HttpClient'
puts '(rest / generation / streaming / download) instead of bare HTTP.'
puts 'Never pass a bare Numeric to .timeout (that caps the whole request and'
puts 'kills healthy streams), and always set write: explicitly (the gem'
puts 'defaults omitted values to 0.25s, breaking large uploads).'

exit 1
