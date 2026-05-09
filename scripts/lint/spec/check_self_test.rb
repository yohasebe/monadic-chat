#!/usr/bin/env ruby
# frozen_string_literal: true

# Meta-test for the anti-pattern lint scripts.
#
# Each lint rule scans the codebase for a specific anti-pattern. If the
# rule's regex breaks, an allow-list silently swallows the target, or a
# SCAN_ROOT is removed by a refactor, the rule will keep returning "OK"
# while no longer catching anything. This script proves each rule still
# fires on a synthetic violation:
#
#   1. Write a temporary file containing a known violation into a path
#      the rule actually scans.
#   2. Invoke the rule via Open3.capture3.
#   3. Assert non-zero exit *and* that the violation file is mentioned
#      in stdout. Cleanup runs in an ensure block.
#
# Run from repo root:
#   ruby scripts/lint/spec/check_self_test.rb
# Exit 0 = all rules detect their target. Exit 1 = some rule is silent.

require 'open3'
require 'fileutils'
require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..', '..').realpath
LINT_DIR = ROOT.join('scripts/lint')

# Fixture targets live inside scanned directories so the rules will
# actually pick them up. The names are deliberately conspicuous and
# leading-underscored so a stray copy is easy to spot in git status.
RUBY_FIXTURE_DIR = ROOT.join('docker/services/ruby/lib/monadic')
ROUTE_FIXTURE_DIR = ROOT.join('docker/services/ruby/lib/monadic/routes')
JS_FIXTURE_DIR = ROOT.join('docker/services/ruby/public/js/monadic')

FIXTURES = {
  ruby: RUBY_FIXTURE_DIR.join('_lint_self_check_fixture.rb'),
  route: ROUTE_FIXTURE_DIR.join('_lint_self_check_route.rb'),
  js: JS_FIXTURE_DIR.join('_lint_self_check.js')
}.freeze

@results = []

def run_lint(script)
  stdout, stderr, status = Open3.capture3('ruby', LINT_DIR.join(script).to_s, chdir: ROOT.to_s)
  [stdout, stderr, status]
end

def with_temp_file(path, content)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
  yield
ensure
  File.unlink(path) if File.exist?(path)
end

def assert(name, condition, detail = nil)
  if condition
    @results << [:pass, name]
    puts "  PASS  #{name}"
  else
    @results << [:fail, name, detail]
    puts "  FAIL  #{name}"
    puts "        #{detail}" if detail
  end
end

def section(label)
  puts ''
  puts "[#{label}]"
end

# ---------------------------------------------------------------------------
# 1. check_personal_paths.rb — must flag a hardcoded /Users/<name>/ literal.
# ---------------------------------------------------------------------------
section 'check_personal_paths.rb'
fixture = FIXTURES[:ruby]
violation = <<~'RUBY'
  # frozen_string_literal: true
  module LintFixture
    HARDCODED = "/Users/someone/monadic/data/file.txt"
  end
RUBY
with_temp_file(fixture, violation) do
  stdout, _stderr, status = run_lint('check_personal_paths.rb')
  assert(
    'detects /Users/<name>/ literal',
    !status.success? && stdout.include?(fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}, stdout did not name fixture\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
# 2. check_shell_escape.rb — must flag docker exec with raw interpolation.
# ---------------------------------------------------------------------------
section 'check_shell_escape.rb'
violation = <<~'RUBY'
  # frozen_string_literal: true
  module LintFixture
    def self.run(user_input)
      `docker exec mycontainer bash -c "ls #{user_input}"`
    end
  end
RUBY
with_temp_file(fixture, violation) do
  stdout, _stderr, status = run_lint('check_shell_escape.rb')
  assert(
    'detects docker exec with raw interpolation',
    !status.success? && stdout.include?(fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}, stdout did not name fixture\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
# 3. check_data_path_literals.rb — must flag bare "/monadic/data" literal.
# ---------------------------------------------------------------------------
section 'check_data_path_literals.rb'
violation = <<~'RUBY'
  # frozen_string_literal: true
  module LintFixture
    DATA = "/monadic/data/somewhere"
  end
RUBY
with_temp_file(fixture, violation) do
  stdout, _stderr, status = run_lint('check_data_path_literals.rb')
  assert(
    'detects bare /monadic/data literal',
    !status.success? && stdout.include?(fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}, stdout did not name fixture\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
# 4. check_xhr_pair.rb — must flag a fetch() callsite without
#    X-Requested-With when its target route uses request.xhr?.
# ---------------------------------------------------------------------------
section 'check_xhr_pair.rb'
route_fixture = FIXTURES[:route]
js_fixture = FIXTURES[:js]
route_body = <<~RUBY
  # frozen_string_literal: true
  # Sinatra fixture — registered globally when loaded, but the lint reads
  # this as static text only, so the registration never executes.
  post "/_lint_self_check_route" do
    if request.xhr?
      content_type :json
      { ok: true }.to_json
    else
      "fallback"
    end
  end
RUBY
js_body = <<~JS
  // Lint fixture: deliberately omits the X-Requested-With header.
  async function callIt() {
    const res = await fetch("/_lint_self_check_route", {
      method: "POST",
      body: JSON.stringify({})
    });
    return res.json();
  }
JS

begin
  FileUtils.mkdir_p(File.dirname(route_fixture))
  File.write(route_fixture, route_body)
  FileUtils.mkdir_p(File.dirname(js_fixture))
  File.write(js_fixture, js_body)

  stdout, _stderr, status = run_lint('check_xhr_pair.rb')
  assert(
    'detects fetch() without X-Requested-With for xhr-gated route',
    !status.success? && stdout.include?('/_lint_self_check_route'),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
ensure
  File.unlink(route_fixture) if File.exist?(route_fixture)
  File.unlink(js_fixture) if File.exist?(js_fixture)
end

# ---------------------------------------------------------------------------
# 5. check_bare_ws_send.rb — must flag a bare ws.send() callsite that
#    lives outside the monadic-ws.js helper.
# ---------------------------------------------------------------------------
section 'check_bare_ws_send.rb'
ws_fixture = FIXTURES[:js]
ws_body = <<~JS
  // Lint fixture: deliberately calls bare ws.send instead of safeWsSend.
  function _selfCheckWs() {
    ws.send(JSON.stringify({ message: 'PING' }));
    window.ws.send(JSON.stringify({ message: 'LOAD' }));
  }
JS
with_temp_file(ws_fixture, ws_body) do
  stdout, _stderr, status = run_lint('check_bare_ws_send.rb')
  assert(
    'detects bare ws.send() outside the monadic-ws.js helper',
    !status.success? && stdout.include?(ws_fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
puts ''
failures = @results.count { |r| r.first == :fail }
total = @results.size
if failures.zero?
  puts "[lint:self_check] OK — #{total}/#{total} rule(s) detected their target."
  exit 0
else
  puts "[lint:self_check] #{failures}/#{total} rule(s) failed to detect their target."
  exit 1
end
