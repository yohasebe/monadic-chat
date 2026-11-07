# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"
require "rbconfig"
require_relative "../../../support/capability_agreement/isolated_run"

# The capability note in each provider's request body
# (spec/support/capability_agreement/request_body_check.rb), checked in a
# process of its own: a HOME with an empty config file, only the variables Ruby
# and Bundler need, and Ruby's network connections stopped from the start.
# This file does not load spec_helper, which reads a config file when it
# loads.
RSpec.describe "Capability note in the request body, in a process of its own" do
  support = CapabilityAgreement::IsolatedRun::SUPPORT
  service_root = File.expand_path("../../../..", __dir__)

  before(:all) do
    @dir = File.realpath(Dir.mktmpdir("capability-request-body-"))
    home = File.join(@dir, "home")
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p([File.join(home, "monadic", "config"), File.join(home, "monadic", "data"), bin])
    # spec_helper takes the first config file it finds: this one.
    File.write(File.join(home, "monadic", "config", "env"), "")
    @events = File.join(@dir, "events")
    report = File.join(@dir, "report.json")
    env = CapabilityAgreement::IsolatedRun.env(home: home, bin: bin, events: @events)
             .merge("TEST_OUTPUT_DIR" => File.join(@dir, "results"))
    argv = [RbConfig.ruby, Gem.bin_path("rspec-core", "rspec"), File.join(support, "request_body_check.rb"),
            "--format", "json", "--out", report, "--failure-exit-code", "0", "--error-exit-code", "1"]
    # A failed example is reported below from the report; an error outside
    # the examples (a load error) or the time limit fails here.
    CapabilityAgreement::IsolatedRun.run(env, argv, chdir: service_root, time_limit: 300)
    @report = JSON.parse(File.read(report))
  end

  after(:all) { FileUtils.rm_rf(@dir) if @dir }

  it "passes every example of the check" do
    failed = @report["examples"].reject { |e| e["status"] == "passed" }
    expect(failed.map { |e| "#{e['full_description']}: #{e.dig('exception', 'message')}" }).to be_empty
    expect(@report.dig("summary", "example_count")).to eq(86)
    expect(@report.dig("summary", "errors_outside_of_examples_count")).to eq(0)
  end

  it "made no connection that got past the stops" do
    lines = File.readlines(@events, chomp: true)
    expect(lines).to include("loaded rspec")
    expect(lines.grep(/\Asocket /)).to be_empty
    # Only the local Ollama lookup when its helper loads, and it was stopped.
    expect(lines.grep(/\Arequest /).uniq - ["request localhost", "request host.docker.internal"]).to be_empty
  end
end
