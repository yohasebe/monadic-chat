# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

class MonadicApp; end unless defined?(MonadicApp)
module OpenAIHelper; end unless defined?(OpenAIHelper)
module MonadicSharedTools; module FileOperations; end; end
require_relative '../../../lib/monadic/adapters/text_to_speech_helper'
require_relative '../../../apps/speech_draft_helper/speech_draft_helper_tools'

# The speech is made in a run folder of the chat's folder and shown on the
# work screen; without a chat it goes to the shared folder as before.
RSpec.describe SpeechDraftHelperOpenAI do
  around do |example|
    Dir.mktmpdir('speech-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  let(:app) { described_class.new }
  let(:workbench) { Struct.new(:chat_id).new(Monadic::Workspace::Ids.generate(:chat)) }

  before do
    stub_const('CONFIG', {})
    allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
    # The speech command: it writes the audio beside its text, named after it.
    allow(app).to receive(:send_command) do |command:, **|
      input = Shellwords.split(command)[1]
      name = "#{File.basename(input, '.*')}.mp3"
      File.binwrite(File.join(File.dirname(input), name), 'MP3')
      "Text-to-speech audio MP3 saved to #{name}"
    end
  end

  it "keeps the speech in a run folder of the chat's folder and shows it" do
    result = app.text_to_speech(text: 'Thank you all', workbench: workbench)
    speech = result[%r{conversations/\S+/artifacts/j_[a-z0-9]+/\S+\.mp3}]
    expect(speech).not_to be_nil
    expect(Dir.children(File.join(@data, File.dirname(speech)))).to eq([File.basename(speech)])
    expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(speech, workbench)
    expect(result).to include('work screen')
    expect(Dir.children(@data)).to eq(['conversations'])
  end

  it 'makes the speech in the shared folder without a chat' do
    result = app.text_to_speech(text: 'Thank you all')
    expect(result).to match(/saved to \S+\.mp3/)
    expect(Dir.children(@data).grep(/\.mp3\z/).size).to eq(1)
  end

  it 'gives back what the command said, and leaves no run folder, when nothing was made' do
    allow(app).to receive(:send_command).and_return('ERROR: OPENAI_API_KEY is not set.')
    expect(app.text_to_speech(text: 'Thank you all', workbench: workbench)).to include('ERROR')
    expect(Dir.glob(File.join(@data, 'conversations/*/artifacts/*'))).to be_empty
  end
end
