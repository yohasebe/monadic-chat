# frozen_string_literal: true

# The capability agreement check, run in a process of its own whose HOME,
# PATH (a fake docker) and network stops (no_network.rb) the spec set up, with
# IN_CONTAINER=false. A case marked "container" runs with IN_CONTAINER=true
# instead, its container paths under MONADIC_TEST_CONTAINER_ROOT
# (container_paths.rb). For each case it writes the config file, the server's
# CONFIG and the docker answers, builds the capability note the way the app
# does, then calls the tools the note reports on through their real code.
# Both go to a JSON file for the spec to compare.
#
#   ruby driver.rb CASES_JSON RESULTS_JSON
#
# A case: { "name", "file" (config file entries), "config" (what the
# server's CONFIG and ENV hold), "op" (the op CLI), "docker" (fake_docker.rb
# answers), and for a container case "container": { "delivered" (the
# delivered file's text, or null for none) } }. The app loads once; each
# case starts from the same state (config file, the settings any case sets,
# resolved references, a new session). A container case checks the note and
# speech only: the readers' docker commands name the container's own paths.
require "json"
require "fileutils"

# The names (never the values) of what this process was started with that it
# should not have: a variable the spec set outside, or a credential.
leaked_env = ENV.keys.grep(/\AMONADIC_TEST_OUTER_|(?:API_KEY|TOKEN|SECRET|PASSWORD)\z/).sort

cases = JSON.parse(File.read(ARGV.fetch(0)))
results_path = ARGV.fetch(1)
events_path = ENV.fetch("MONADIC_TEST_NET_EVENTS")
docker_log = ENV.fetch("MONADIC_TEST_DOCKER_LOG")
docker_state = ENV.fetch("MONADIC_TEST_DOCKER_STATE")

CONFIG = {}
APPS = {}.freeze

lib = File.expand_path("../../../lib/monadic", __dir__)
require File.join(lib, "app")
require File.join(lib, "shared_tools/registry")
require File.join(lib, "utils/capability_notes")
%w[read_write_helper text_to_speech_helper file_analysis_helper].each do |helper|
  require File.join(lib, "adapters", helper)
end

def tool(name)
  { "type" => "function", "function" => { "name" => name, "description" => "" } }
end

SETTINGS = {
  "provider" => "openai",
  "tools" => %w[fetch_text_from_pdf fetch_text_from_office text_to_speech analyze_image].map { |n| tool(n) },
  imported_tool_groups: [{ name: :image_analysis, visibility: "always" }]
}.freeze

# Lines written since the last call: the hosts requests were stopped for
# ("request"), connections that got past those stops ("socket"), and the
# processes the stops were loaded in ("loaded").
def take_events(path)
  lines = File.exist?(path) ? File.readlines(path, chomp: true) : []
  File.write(path, "")
  %w[request socket loaded].to_h do |kind|
    [kind, lines.grep(/\A#{kind} /).map { |l| l.delete_prefix("#{kind} ") }]
  end
end

def take_calls(path)
  calls = File.exist?(path) ? File.readlines(path, chomp: true).map { |l| JSON.parse(l) } : []
  File.write(path, "")
  calls
end

container_root = ENV.fetch("MONADIC_TEST_CONTAINER_ROOT")
delivered_path = File.join(container_root, Monadic::Utils::SecretReferences::DELIVERED_PATH)
# The app's container paths for scripts and the shared folder: the bundled
# scripts and the shared folder under the container root.
path_constants = {
  false => { SYSTEM_SCRIPT_DIR: MonadicApp::SYSTEM_SCRIPT_DIR, SHARED_VOL: MonadicApp::SHARED_VOL },
  true => { SYSTEM_SCRIPT_DIR: MonadicApp::LOCAL_SYSTEM_SCRIPT_DIR,
            SHARED_VOL: File.join(container_root, "monadic", "data") }
}
use_paths = lambda do |in_container|
  ENV["IN_CONTAINER"] = in_container.to_s
  path_constants.fetch(in_container).each do |name, value|
    MonadicApp.send(:remove_const, name)
    MonadicApp.const_set(name, value)
  end
end

app = Class.new(MonadicApp) { include MonadicHelper }.new
app.settings = SETTINGS
startup = take_events(events_path)
# Every setting a case can put in CONFIG and ENV; each case starts without them.
managed = cases.flat_map { |c| c.fetch("config").keys }.uniq

results = cases.map do |kase|
  container = kase["container"]
  use_paths.call(!container.nil?)
  FileUtils.rm_f(delivered_path)
  File.write(delivered_path, container["delivered"]) if container && container["delivered"]
  File.write(Monadic::Utils::Environment.env_path, kase.fetch("file").map { |k, v| "#{k}=#{v}\n" }.join)
  managed.each do |key|
    CONFIG.delete(key)
    ENV.delete(key)
  end
  kase.fetch("config").each { |key, value| CONFIG[key] = ENV[key] = value }
  File.write(docker_state, JSON.generate(kase.fetch("docker")))
  Monadic::Utils::SecretReferences.reset!
  # A case with "started": the server read its references from that config
  # file and op when it started; the file and op then change, and the same
  # server goes on.
  if (started = kase["started"])
    File.write(Monadic::Utils::Environment.env_path, started.fetch("file").map { |k, v| "#{k}=#{v}\n" }.join)
    ENV["MONADIC_OP_CLI"] = started.fetch("op")
    Monadic::Utils::SecretReferences.resolved
    File.write(Monadic::Utils::Environment.env_path, kase.fetch("file").map { |k, v| "#{k}=#{v}\n" }.join)
  end
  ENV["MONADIC_OP_CLI"] = kase.fetch("op")
  setup_events = take_events(events_path)
  take_calls(docker_log)

  session = { parameters: { "app_name" => "AgreementApp" } }
  note = Monadic::Utils::CapabilityNotes.build(settings: SETTINGS, session: session, app_name: "AgreementApp",
                                                config: CONFIG)
  note_events = take_events(events_path)
  probe_calls = take_calls(docker_log)

  speech = Monadic::Utils::TtsProvider::API_KEYS.keys.to_h do |provider|
    text = app.text_to_speech(provider: provider, text: "Hello.")
    [provider, take_events(events_path).merge("text" => text.to_s)]
  end

  result = { "name" => kase.fetch("name"), "container" => !container.nil?, "setup_events" => setup_events,
             "note" => note.to_s, "note_events" => note_events, "probe_calls" => probe_calls, "speech" => speech }
  next result if container

  readers = {
    "pdf" => app.fetch_text_from_pdf(pdf: "doc.pdf").to_s,
    "office" => app.fetch_text_from_office(file: "doc.docx").to_s
  }
  reader_events = take_events(events_path)
  reader_calls = take_calls(docker_log)

  image_text = app.analyze_image(message: "What is this?", image_path: "pic.png").to_s
  image = take_events(events_path).merge("text" => image_text)

  result.merge("readers" => readers, "reader_events" => reader_events, "reader_calls" => reader_calls,
               "image" => image)
end

File.write(results_path, JSON.generate("leaked_env" => leaked_env, "startup" => startup, "cases" => results))
