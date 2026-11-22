# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"
require_relative "../../../lib/monadic/utils/env_file"
require_relative "../../../lib/monadic/utils/capability_notes"
require_relative "../../../lib/monadic/utils/trial_log"

# The capability notes and the trial log are turned on from the shell only.
# Written in the config file, they are not used: not put in ENV, not among
# the accepted settings, and neither feature turns on.
RSpec.describe "Flags set only from the shell" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:log_dir) { File.join(@dir, "trial").tap { |d| Dir.mkdir(d) } }
  let(:config) do
    File.join(@dir, "env").tap do |path|
      File.write(path, <<~ENV)
        EXTRA_LOGGING=true
        MONADIC_CAPABILITY_NOTES=SpeechDraftHelperOpenAI
        MONADIC_TRIAL_LOG=#{log_dir}
      ENV
    end
  end
  let(:flags) { [Monadic::Utils::CapabilityNotes::FLAG, Monadic::Utils::TrialLog::FLAG] }

  it "names both flags among the settings the file may not set" do
    expect(Monadic::Utils::EnvFile.refused_keys(config)).to include(*flags)
  end

  it "keeps them out of the accepted settings and out of ENV, while an ordinary setting gets in" do
    env = {}
    accepted = Monadic::Utils::EnvFile.load!(config, env: env, out: StringIO.new)

    expect(env["EXTRA_LOGGING"]).to eq("true")
    expect(accepted.keys).not_to include(*flags)
    expect(env.keys).not_to include(*flags)
  end

  it "leaves both features off when the file is all that sets them" do
    env = {}
    Monadic::Utils::EnvFile.load!(config, env: env, out: StringIO.new)

    expect(Monadic::Utils::CapabilityNotes.enabled_for?("SpeechDraftHelperOpenAI", env)).to be false
    expect(Monadic::Utils::TrialLog.dir(env)).to be_nil
    Monadic::Utils::TrialLog.usage({ "input_tokens" => 1 }, app: "A", env: env)
    expect(Dir.children(log_dir)).to be_empty
  end
end
