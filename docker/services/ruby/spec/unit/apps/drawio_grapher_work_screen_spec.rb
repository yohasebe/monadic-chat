# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../apps/drawio_grapher/drawio_grapher_tools'

# A diagram is kept in a run folder of the chat's folder and shown on the
# work screen; the reply carries only a notice with its path.
RSpec.describe DrawIOGrapher do
  around do |example|
    Dir.mktmpdir('drawio-work-screen-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p(@data)
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(MonadicSharedTools::WorkbenchTools).to receive(:show_file).and_return('{"status":"shown_in_work_screen"}')
  end

  let(:app) { Class.new { include DrawIOGrapher }.new }
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:workbench) { Struct.new(:chat_id).new(chat) }
  let(:diagram) do
    '<mxfile><diagram id="d" name="Page-1"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>' \
      '</root></mxGraphModel></diagram></mxfile>'
  end

  it "keeps the diagram in the chat's folder, shows it, and tells the model to say only where it is" do
    result = app.preview_drawio(content: diagram, filename: 'order flow', workbench: workbench)
    path = result[%r{conversations/\S+/artifacts/j_[a-z0-9]+/order flow\.drawio}]
    expect(path).not_to be_nil
    expect(File.read(File.join(@data, path))).to eq(diagram)
    expect(MonadicSharedTools::WorkbenchTools).to have_received(:show_file).with(path, workbench)
    expect(result).to include('work screen', 'do not put its content')
    expect(Dir.children(@data)).to eq(['conversations'])
  end

  it 'keeps the repaired diagram when the XML was only cells' do
    result = app.preview_drawio(content: '<mxCell id="2" value="A" vertex="1" parent="1"/>', workbench: workbench)
    path = result[%r{conversations/\S+/diagram\.drawio}]
    expect(File.read(File.join(@data, path))).to include('<mxfile', 'value="A"')
  end

  it 'refuses a file name with a folder in it, and keeps nothing without a chat' do
    %w[../x a/b .hidden].each do |name|
      expect(app.preview_drawio(content: diagram, filename: name, workbench: workbench)).to start_with('❌')
    end
    expect(app.preview_drawio(content: diagram)).to start_with('❌')
    expect(Dir.exist?(File.join(@data, 'conversations'))).to be false
  end
end
