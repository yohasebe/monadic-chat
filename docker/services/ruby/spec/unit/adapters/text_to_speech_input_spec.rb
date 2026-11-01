# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../lib/monadic/adapters/text_to_speech_helper"

# The text written for the speech command is only its input: it is there
# while the command runs and gone afterwards, whether the command worked.
RSpec.describe "Text-to-speech input file" do
  let(:helper) do
    Class.new do
      include MonadicHelper
      attr_reader :seen
      attr_accessor :outcome

      def send_command(command:, container:)
        path = Shellwords.split(command)[1]
        @seen = File.exist?(path) ? File.read(path) : nil
        raise outcome if outcome.is_a?(Exception)

        outcome
      end
    end.new
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@dir)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@dir)
    stub_const("CONFIG", {})
  end

  it "gives the command the text, then removes it when the command worked" do
    helper.outcome = "speech.mp3"
    expect(helper.text_to_speech(text: "Thank you all")).to eq("speech.mp3")
    expect(helper.seen).to eq("Thank you all")
    expect(Dir.children(@dir)).to be_empty
  end

  it "removes it when the command reports an error" do
    helper.outcome = "ERROR: GEMINI_API_KEY is not set."
    helper.text_to_speech(text: "Thank you all", provider: "gemini")
    expect(helper.seen).to eq("Thank you all")
    expect(Dir.children(@dir)).to be_empty
  end

  it "removes it when the command raises" do
    helper.outcome = RuntimeError.new("stopped")
    expect { helper.text_to_speech(text: "Thank you all") }.to raise_error(RuntimeError)
    expect(Dir.children(@dir)).to be_empty
  end

  it "leaves the other files of the shared folder alone" do
    File.write(File.join(@dir, "notes.md"), "mine")
    helper.outcome = "speech.mp3"
    helper.text_to_speech(text: "Thank you all")
    expect(Dir.children(@dir)).to eq(["notes.md"])
  end
end
