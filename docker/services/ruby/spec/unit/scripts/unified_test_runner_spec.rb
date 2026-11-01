# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../../../../lib/test_runner"

# The developer test runner (rake test:run / test:profile): a profile's
# settings are applied, every suite runs, and a failed suite fails the run.
RSpec.describe TestRunner do
  let(:profile_yaml) do
    <<~YAML
      profiles:
        two:
          description: "two suites"
          suites: [unit, integration]
          api_level: none
          format: progress
          timeout: 42
          providers: [openai, anthropic]
    YAML
  end

  around do |example|
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test-config.yml")
      File.write(path, profile_yaml)
      saved = ENV.to_h.slice("TEST_PROFILE_PATH", "PROVIDERS", "API_TIMEOUT")
      ENV["TEST_PROFILE_PATH"] = path
      example.run
    ensure
      %w[TEST_PROFILE_PATH PROVIDERS API_TIMEOUT].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
    end
  end

  def runner_with(results)
    runner = described_class.new(nil)
    expect(runner.load_profile("two")).to be true
    commands = []
    runner.define_singleton_method(:setup_environment) {}
    runner.define_singleton_method(:sh_safe) { |cmd| commands << cmd; results.shift }
    allow(Dir).to receive(:chdir).and_yield
    [runner, commands]
  end

  it "applies the profile's format, timeout and providers and runs every suite" do
    runner, commands = runner_with([true, true])
    expect(runner.execute).to be true
    expect(commands).to eq(["bundle exec rspec spec/unit --format progress",
                            "bundle exec rspec spec/integration --format progress"])
    expect(ENV["API_TIMEOUT"]).to eq("42")
    expect(ENV["PROVIDERS"]).to eq("openai,anthropic")
  end

  it "runs the remaining suites after a failure and reports the run as failed" do
    runner, commands = runner_with([false, true])
    expect(runner.execute).to be false
    expect(commands.size).to eq(2)
  end

  it "fails a single suite run when the suite fails" do
    runner = described_class.new("unit", "format=progress")
    runner.define_singleton_method(:setup_environment) {}
    runner.define_singleton_method(:sh_safe) { |_cmd| false }
    allow(Dir).to receive(:chdir).and_yield
    expect(runner.execute).to be false
  end

  it "saves results under the repository's tmp/test_results" do
    made = []
    allow(FileUtils).to receive(:mkdir_p) { |dir| made << dir }
    runner = described_class.new("unit", "save=true,format=progress")
    runner.define_singleton_method(:setup_environment) {}
    runner.define_singleton_method(:sh_safe) { |_cmd| true }
    allow(Dir).to receive(:chdir).and_yield
    allow(runner).to receive(:warn)
    runner.execute
    repo = File.expand_path("../../../../../..", __dir__)
    expect(made).to include(File.join(repo, "tmp/test_results"))
  end
end
