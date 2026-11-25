# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../../lib/monadic/utils/websocket'

# A new whiteboard asked for from the page: plain, or drawn on an image of
# the work screen at the version the page showed.
RSpec.describe 'A new whiteboard from the page' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= []
      end

      def send_to_client(_connection, payload)
        sent << payload
      end
    end.new
  end
  let(:chat) { Monadic::Workspace::Ids.generate(:chat) }
  let(:session) { { chat_id: chat, _ws_generation: 1, parameters: { 'app_name' => 'ChatOpenAI' } } }
  let(:store) { Monadic::Workbench::Store.new(File.join(@state, 'workbench')) }
  let(:origin) { { actor: :user, source: :panel, tab: 'tab-wb', generation: 1 } }

  def png(width, height)
    "\x89PNG\r\n\x1A\n".b + [13].pack('N') + 'IHDR'.b + [width, height].pack('NN') + "\x08\x02\x00\x00\x00".b +
      "\x00".b * 4
  end

  around do |example|
    Dir.mktmpdir('whiteboard-handler-spec') do |dir|
      @data = File.join(dir, 'data')
      @state = File.join(dir, 'state')
      FileUtils.mkdir_p([@data, @state])
      @data = File.realpath(@data)
      example.run
    end
  end

  before do
    Thread.current[:websocket_session_id] = 'tab-wb'
    Monadic::Workbench::Board.reset!
    Monadic::Workbench::Board.live = ->(t) { t == 'tab-wb' ? 1 : nil }
    allow(WebSocketHelper).to receive(:live_generation) { |t| t == 'tab-wb' ? 1 : nil }
    allow(Monadic::Workbench::Store).to receive(:default).and_return(store)
    allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@data)
    allow(Monadic::Utils::Environment).to receive(:state_path).and_return(@state)
    allow(Monadic::Workbench::Channel).to receive(:changed)
  end

  after do
    Thread.current[:websocket_session_id] = nil
    Monadic::Workspace::Ledger.clear_unsettled!
  end

  def board = Monadic::Workbench::Board.for(chat, store: store)

  def photo
    FileUtils.mkdir_p(File.join(@data, 'photos'))
    File.binwrite(File.join(@data, 'photos/a.png'), png(300, 400))
    item, = board.add_file(path: 'photos/a.png', origin: origin, epoch: Monadic::Workspace::Chats.epoch(chat))
    item
  end

  def ask(fields)
    host.send(:handle_ws_workbench_whiteboard, nil, { 'message' => 'WORKBENCH_WHITEBOARD_NEW', 'request' => 7 }.merge(fields),
              session)
    host.sent.find { |m| m['type'] == 'workbench_whiteboard' }
  end

  def kept(item_id) = JSON.parse(File.read(File.join(@data, board.item(item_id).dig('file', 'path'))))

  it 'makes a whiteboard on the image the page names, at the version it showed, and selects it for the tab' do
    image = photo
    reply = ask('item_id' => image['id'], 'version' => image.dig('file', 'sha256'))
    expect(reply).to include('status' => 'saved', 'request' => 7)
    expect(kept(reply['item_id'])).to include('version' => 2, 'width' => 1200, 'height' => 1600)
    expect(board.selected(tab: 'tab-wb', generation: 1)).to eq(reply['item_id'])
  end

  it 'makes none on a version the page did not show, and a plain one when it names no image' do
    image = photo
    reply = ask('item_id' => image['id'], 'version' => 'f' * 64)
    expect(reply).to include('status' => 'refused')
    expect(reply['reason']).to include('changed')
    host.sent.clear
    plain = ask({})
    expect(kept(plain['item_id'])).to include('version' => 1, 'width' => 1600, 'height' => 1000)
  end
end
