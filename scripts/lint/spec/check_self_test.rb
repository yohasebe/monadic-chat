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

DOCS_FIXTURE_DIR = ROOT.join('docs')

FIXTURES = {
  ruby: RUBY_FIXTURE_DIR.join('_lint_self_check_fixture.rb'),
  route: ROUTE_FIXTURE_DIR.join('_lint_self_check_route.rb'),
  js: JS_FIXTURE_DIR.join('_lint_self_check.js'),
  docs: DOCS_FIXTURE_DIR.join('_lint_self_check.md')
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
# 6. check_global_shadow_delegation.rb — must flag a top-level same-name
#    wrapper delegating to window (infinite recursion in classic scripts).
# ---------------------------------------------------------------------------
section 'check_global_shadow_delegation.rb'
shadow_fixture = FIXTURES[:js]
shadow_body = <<~JS
  // Lint fixture: top-level same-name delegation wrapper (classic-script
  // shadowing → infinite recursion at runtime).
  function shadowedHelper(text) {
    return window.shadowedHelper(text);
  }
JS
with_temp_file(shadow_fixture, shadow_body) do
  stdout, _stderr, status = run_lint('check_global_shadow_delegation.rb')
  assert(
    'detects top-level same-name window-delegation wrapper',
    !status.success? && stdout.include?(shadow_fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
# 7. check_http_timeout.rb — must flag an outbound http gem call whose chain
#    carries no timeout (the gem has no default, so the thread hangs forever).
#    The fixture also pins that a `.timeout(` belonging to a LATER, unrelated
#    statement does not clear the earlier violation.
# ---------------------------------------------------------------------------
section 'check_http_timeout.rb'
http_fixture = FIXTURES[:ruby]
http_body = <<~'RUBY'
  # Lint fixture: untimed outbound HTTP call.
  module LintHttpFixture
    def untimed(url, headers, body)
      HTTP.headers(headers).post(url, json: body)
    end

    def timed(url, headers, body)
      HTTP.headers(headers)
          .timeout(connect: 30, read: 120, write: 60)
          .post(url, json: body)
    end
  end
RUBY
with_temp_file(http_fixture, http_body) do
  stdout, _stderr, status = run_lint('check_http_timeout.rb')
  assert(
    'detects an outbound HTTP call with no timeout in its chain',
    !status.success? && stdout.include?(http_fixture.relative_path_from(ROOT).to_s),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
section 'check_docs_links.rb'
docs_fixture = FIXTURES[:docs]

# A heading anchor is whatever docsify's slugify() produces, so the cases
# below pin the parts that are easy to get wrong: an explicit :id= wins over
# the heading text, and Japanese punctuation is kept rather than stripped.
docs_body = <<~'MARKDOWN'
  # Lint fixture

  ## Known Good Heading :id=lint-self-check-good

  ## 日本語の見出し（丸括弧）

  - [resolves via the explicit id](#lint-self-check-good)
  - [resolves via the Japanese slug](#日本語の見出し（丸括弧）)
  - [does not resolve: id typo](#lint-self-check-typo)
  - [does not resolve: parentheses dropped](#日本語の見出し丸括弧)
MARKDOWN

with_temp_file(docs_fixture, docs_body) do
  stdout, _stderr, status = run_lint('check_docs_links.rb')
  relative = docs_fixture.relative_path_from(ROOT).to_s

  assert(
    'detects a heading anchor that no heading produces',
    !status.success? && stdout.include?('lint-self-check-typo'),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
  assert(
    'applies docsify slug rules to non-ASCII headings',
    stdout.include?('日本語の見出し丸括弧'),
    "stdout:\n#{stdout}"
  )
  assert(
    'accepts the anchors that do resolve',
    !stdout.include?('lint-self-check-good') &&
      !stdout.include?('#日本語の見出し（丸括弧）'),
    "stdout:\n#{stdout}"
  )
  assert(
    'reports the file the broken anchors live in',
    stdout.include?(relative),
    "stdout:\n#{stdout}"
  )
end

# Links written as published-site URLs name files in docs/, so they are
# resolved rather than skipped as external. Both spellings docsify accepts
# for a heading anchor are covered.
site_body = <<~'MARKDOWN'
  # Lint fixture

  ## Known Good Heading :id=lint-self-check-good

  - [resolves](https://yohasebe.github.io/monadic-chat/#/_lint_self_check#lint-self-check-good)
  - [resolves via ?id=](https://yohasebe.github.io/monadic-chat/#/_lint_self_check?id=lint-self-check-good)
  - [missing page](https://yohasebe.github.io/monadic-chat/#/_lint_self_check_absent)
  - [missing anchor](https://yohasebe.github.io/monadic-chat/#/_lint_self_check#lint-self-check-absent)
MARKDOWN

with_temp_file(docs_fixture, site_body) do
  stdout, _stderr, status = run_lint('check_docs_links.rb')

  assert(
    'follows a published-site URL to a page that does not exist',
    !status.success? && stdout.include?('_lint_self_check_absent'),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
  assert(
    'checks the anchor of a published-site URL',
    stdout.include?('lint-self-check-absent'),
    "stdout:\n#{stdout}"
  )
  assert(
    'accepts both the # and ?id= anchor spellings',
    !stdout.include?('lint-self-check-good'),
    "stdout:\n#{stdout}"
  )
end

# An image written with no alt text is still a link to a file that has to
# exist, so it must not fall outside the link pattern.
image_body = <<~'MARKDOWN'
  # Lint fixture

  ![](./assets/images/monadic-chat-logo.png ':size=200')
  ![](./assets/images/_lint_self_check_absent.png ':size=200')
MARKDOWN

with_temp_file(docs_fixture, image_body) do
  stdout, _stderr, status = run_lint('check_docs_links.rb')

  assert(
    'detects an image with no alt text whose file is missing',
    !status.success? && stdout.include?('_lint_self_check_absent.png'),
    "exit=#{status.exitstatus}\nstdout:\n#{stdout}"
  )
  assert(
    'accepts an image whose file is present',
    !stdout.include?('monadic-chat-logo.png'),
    "stdout:\n#{stdout}"
  )
end

# ---------------------------------------------------------------------------
section 'help dump shipping gate'

# The help dump is generated rather than tracked, so the only thing standing
# between a developer dump and a release is this gate. It runs at build time,
# never in CI, which is exactly the shape that rots unnoticed.
#
# These cases drive HelpDumpGuard against fixtures in a temporary directory.
# Checking the real dump instead would make the whole section skip on a clean
# checkout (the dump is generated) and would rewrite build output as a side
# effect of running the tests.
require 'json'
require 'tmpdir'
require_relative '../../help_dump_guard'

# Shaped like what process_documentation.rb writes: every point carries an id,
# a payload hash and a boolean is_internal.
def help_item_point(id = 1, is_internal: false)
  { 'id' => id, 'payload' => { 'text' => 'body', 'is_internal' => is_internal } }
end

def help_dump_fixture(docs: [], items: [help_item_point])
  { 'collections' => { 'help_docs' => { 'points' => docs },
                       'help_items' => { 'points' => items } } }
end

def help_doc_point(path, is_internal: false, root_doc: false, id: 1)
  payload = { 'file_path' => path, 'is_internal' => is_internal }
  payload['metadata'] = { 'is_root_doc' => true } if root_doc
  { 'id' => id, 'payload' => payload }
end

# Every case names a file that really is (or really is not) in the tree, so the
# fixtures stay honest about what the guard resolves paths against.
Dir.mktmpdir('help_dump_guard') do |tmp|
  dump = Pathname.new(tmp).join('help_db.json')
  # A guard that raises is as broken as a guard that returns nothing, and a
  # dead script reports neither. Turn the exception into a problem string that
  # deliberately shares no wording with the real messages, so an assertion
  # looking for specific wording still fails.
  check = lambda do |data|
    dump.write(JSON.generate(data))
    begin
      HelpDumpGuard.problems(dump_path: dump, root: ROOT)
    rescue StandardError => e
      ["guard raised #{e.class}: #{e.message}"]
    end
  end

  real_doc = 'advanced-topics/help-system.md'

  problems = check.call(help_dump_fixture(docs: [help_doc_point(real_doc)]))
  assert('accepts a public-only help dump', problems.empty?, problems.join("\n"))

  problems = check.call(help_dump_fixture(
    docs: [help_doc_point(real_doc), help_doc_point('developer/notes.md', is_internal: true, id: 2)]
  ))
  assert(
    'refuses a help dump whose help_docs carry internal documents',
    problems.any? { |m| m.include?('internal point') }, problems.join("\n")
  )

  # Internal content can sit in help_items alone: the chunks ship the text even
  # when no document-level point names the file.
  problems = check.call(help_dump_fixture(
    docs: [help_doc_point(real_doc)],
    items: [help_item_point(2, is_internal: true)]
  ))
  assert(
    'refuses a help dump whose internal content is only in help_items',
    problems.any? { |m| m.include?('internal point') }, problems.join("\n")
  )

  problems = check.call(help_dump_fixture(
    docs: [help_doc_point(real_doc), help_doc_point('basic-usage/_absent_page.md', id: 2)]
  ))
  assert(
    'refuses a help dump that names a deleted document',
    problems.any? { |m| m.include?('_absent_page.md') }, problems.join("\n")
  )

  # Root README/CHANGELOG are stored bare with is_root_doc. Resolving them
  # under docs/ sends the changelog to docs/CHANGELOG.md, which only exists on
  # a case-insensitive filesystem -- green on macOS, red on CI.
  problems = check.call(help_dump_fixture(
    docs: [help_doc_point('README.md', root_doc: true, id: 1),
           help_doc_point('CHANGELOG.md', root_doc: true, id: 2)]
  ))
  assert(
    'accepts root README and CHANGELOG stored with is_root_doc',
    problems.empty?, problems.join("\n")
  )

  problems = check.call(help_dump_fixture(docs: [help_doc_point('CHANGELOG.md')]))
  assert(
    'refuses a docs-relative path whose case does not match the tree',
    problems.any? { |m| m.include?('CHANGELOG.md') }, problems.join("\n")
  )

  problems = check.call({})
  assert(
    'refuses a dump with no collections',
    problems.any? { |m| m.include?('collections') }, problems.join("\n")
  )

  problems = check.call(help_dump_fixture(docs: [help_doc_point(real_doc)], items: []))
  assert(
    'refuses a dump with an empty help_items collection',
    problems.any? { |m| m.include?('help_items') }, problems.join("\n")
  )

  # A point the guard cannot read is a point it cannot clear for shipping.
  # Skipping it would let a dump full of nulls look like a clean public dump.
  problems = check.call(help_dump_fixture(docs: [nil], items: [nil]))
  assert(
    'refuses a dump whose points are null',
    problems.any? { |m| m.include?('malformed') }, problems.join("\n")
  )

  problems = check.call(help_dump_fixture(docs: [{ 'id' => 1 }]))
  assert(
    'refuses a point with no payload',
    problems.any? { |m| m.include?('malformed') }, problems.join("\n")
  )

  problems = check.call(help_dump_fixture(
    docs: [{ 'id' => 1, 'payload' => { 'file_path' => real_doc, 'is_internal' => 'no' } }]
  ))
  assert(
    'refuses a point whose is_internal is not a boolean',
    problems.any? { |m| m.include?('malformed') }, problems.join("\n")
  )

  problems = check.call(
    { 'collections' => { 'help_docs' => [], 'help_items' => { 'points' => [help_item_point] } } }
  )
  assert(
    'reports a non-hash collection instead of raising',
    problems.any? { |m| m.include?('help_docs') }, problems.join("\n")
  )
end

# ---------------------------------------------------------------------------
section 'before_pack.js (packaging entry point)'

# electron-builder copies the staged payload via extraResources, so the npm
# build scripts never run stage_docker_payload.rb. The hook is the only thing
# checking the dump on that path.
assert(
  'npm packaging runs the help dump check via beforePack',
  JSON.parse(ROOT.join('package.json').read).dig('build', 'beforePack').to_s
      .include?('before_pack'),
  'package.json build.beforePack does not point at the hook'
)

# Asserting that the file mentions the staged path only proves the wiring. Run
# the hook against a fixture payload root so its resolve/reject behaviour is
# checked too -- that is where a "missing dump is fine" branch would hide.
def run_before_pack(payload_root)
  # The heredoc interpolates, so the JS avoids backslash escapes entirely:
  # a literal "\n" here would reach node as a real newline and break the script.
  script = <<~JS
    const hook = require(#{ROOT.join('scripts/before_pack.js').to_s.dump});
    try {
      hook.verifyStagedHelpDump(#{payload_root.to_s.dump}, #{ROOT.to_s.dump});
      console.log('RESOLVED');
    } catch (e) {
      console.log('REJECTED: ' + String(e.message).split(String.fromCharCode(10)).join(' | '));
    }
  JS
  stdout, stderr, status = Open3.capture3('node', '-e', script)
  stdout.empty? ? "no output (exit=#{status.exitstatus})\nstderr:\n#{stderr}" : stdout
end

Dir.mktmpdir('before_pack') do |tmp|
  staged = Pathname.new(tmp).join('build/app-payload/docker/services/ruby/help_data')
  staged.mkpath
  dump = staged.join('help_db.json')

  # app-builder-lib's copyFiles only logs `file source doesn't exist` for a
  # missing extraResources source, so an unstaged payload would otherwise
  # produce an installer with no help database at all.
  assert(
    'the beforePack hook refuses a payload with no staged dump',
    run_before_pack(tmp).include?('REJECTED'),
    run_before_pack(tmp)
  )

  dump.write(JSON.generate(help_dump_fixture(
    docs: [help_doc_point('advanced-topics/help-system.md')]
  )))
  assert(
    'the beforePack hook accepts a staged public-only dump',
    run_before_pack(tmp).include?('RESOLVED'),
    run_before_pack(tmp)
  )

  dump.write(JSON.generate(help_dump_fixture(
    docs: [help_doc_point('advanced-topics/help-system.md'),
           help_doc_point('developer/notes.md', is_internal: true, id: 2)]
  )))
  assert(
    'the beforePack hook refuses a staged dump carrying internal documents',
    run_before_pack(tmp).include?('REJECTED'),
    run_before_pack(tmp)
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
