# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/websocket'

RSpec.describe 'Opening an address on the work screen from the page' do
  let(:host) do
    Class.new do
      include WebSocketHelper
      def sent
        @sent ||= Queue.new
      end

      def send_to_client(_connection, payload)
        sent << payload
      end

      def send_or_broadcast(json, _tab)
        sent << JSON.parse(json)
      end
    end.new
  end
  let(:session) { { chat_id: Monadic::Workspace::Ids.generate(:chat) } }
  let(:opener) { double('page browser host') }
  # The chat's board: the turn's one address is taken there first.
  let(:slots) { double('board', reserve_slot: 'slot-1', release_slot: nil) }

  before do
    Thread.current[:websocket_session_id] = 'tab-open-url'
    allow(Monadic::Workbench::Board).to receive(:for).with(session[:chat_id]).and_return(slots)
    allow(WebSocketHelper).to receive(:page_browser_host).and_return(double(new: opener))
    allow(Monadic::Workbench::UrlFile).to receive(:put).and_return(nil)
  end

  after { Thread.current[:websocket_session_id] = nil }

  def answer
    Timeout.timeout(5) { host.sent.pop }
  end

  it 'opens an http or https address for the tab\'s chat, in a thread of its own' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    seen = Queue.new
    allow(opener).to receive(:start_browser) do |url:|
      seen << [url, Thread.current[:rack_session], Thread.current[:websocket_session_id]]
      { success: true }
    end

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => ' https://example.com/a?b=1 ' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => true)
    expect(seen.pop).to eq(['https://example.com/a?b=1', session, 'tab-open-url'])
  end

  it 'refuses an address that is not http or https, or is too long, without starting anything' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    expect(opener).not_to receive(:start_browser)

    ['file:///etc/passwd', 'javascript:alert(1)', 'example.com', "https://example.com/#{'a' * 2000}"].each do |url|
      host.send(:handle_ws_workbench_open_url, nil, { 'url' => url }, session)
      expect(answer).to eq('type' => 'workbench_open_url', 'success' => false, 'error' => 'invalid_url')
    end
  end

  it 'starts the browser\'s containers and says so when the browser is not there yet' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(false)
    started = []
    allow(Monadic::Utils::ContainerDependencies).to receive(:start_service_async) { |service, **| started << service }
    expect(opener).not_to receive(:start_browser)

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => false, 'error' => 'browser_starting')
    expect(started).to eq(%i[python selenium])
  end

  it 'says the page did not open when the browser could not start' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    allow(opener).to receive(:start_browser).and_return({ success: false, error: 'no' })

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => false, 'error' => 'open_failed')
  end

  it 'puts a PDF the address serves on the work screen as a file, for the tab, without the browser' do
    connected = session.merge(_ws_generation: 3)
    allow(WebSocketHelper::WORKBENCH_LIVE).to receive(:call).with('tab-open-url').and_return(3)
    expect(opener).not_to receive(:start_browser)
    expect(Monadic::Workbench::UrlFile).to receive(:put)
      .with('https://example.com/paper.pdf', connected, tab: 'tab-open-url', generation: 3,
                                                      live: WebSocketHelper::WORKBENCH_LIVE)
      .and_return({ 'as_file' => true, 'item_id' => 'i_paper' })

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com/paper.pdf' }, connected)

    expect(answer).to eq('type' => 'workbench_open_url', 'as_file' => true, 'item_id' => 'i_paper', 'success' => true)
  end

  it 'says why a PDF was not put on the work screen, without the browser' do
    expect(opener).not_to receive(:start_browser)
    allow(Monadic::Workbench::UrlFile).to receive(:put).and_raise(Monadic::Workbench::UrlFile::Failed.new('too_large'))

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com/big.pdf' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'as_file' => true, 'error' => 'too_large', 'success' => false)
  end

  it 'names the browser item of the board when the page opened' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    allow(opener).to receive(:start_browser).and_return({ success: true })
    board = double('board', snapshot: { items: [{ id: 'i_file', kind: 'file' }, { id: 'i_browser', kind: 'browser' }] })
    allow(Monadic::Workbench::Board).to receive(:existing).with(session[:chat_id]).and_return(board)

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => true, 'item_id' => 'i_browser')
  end

  it 'takes the turn\'s one address for the tab before anything is fetched, and keeps it when the page opened' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    allow(opener).to receive(:start_browser).and_return({ success: true })
    expect(slots).to receive(:reserve_slot)
      .with('url', origin: { actor: :user, source: :panel, tab: 'tab-open-url', generation: nil },
                   epoch: Monadic::Workspace::Chats.epoch(session[:chat_id]))
      .and_return('slot-1')
    expect(slots).not_to receive(:release_slot)

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to include('success' => true)
  end

  it 'refuses a second address in the turn before anything is fetched' do
    allow(slots).to receive(:reserve_slot)
      .and_raise(Monadic::Workbench::Board::Refused, Monadic::Workbench::Board::URL_USED)
    expect(Monadic::Workbench::UrlFile).not_to receive(:put)
    expect(opener).not_to receive(:start_browser)

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => false, 'error' => 'url_used')
  end

  it 'gives the turn\'s address back, by its reservation, when neither a file nor a page was placed' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    allow(opener).to receive(:start_browser).and_return({ success: false, error: 'no' })
    allow(Monadic::Workbench::UrlFile).to receive(:put).and_return(nil)
    expect(slots).to receive(:release_slot).with('url', 'slot-1')

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com' }, session)

    expect(answer).to include('success' => false)
  end

  it 'gives it back when a PDF could not be put on the work screen' do
    allow(Monadic::Workbench::UrlFile).to receive(:put).and_raise(Monadic::Workbench::UrlFile::Failed.new('too_large'))
    expect(slots).to receive(:release_slot).with('url', 'slot-1')

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com/big.pdf' }, session)

    expect(answer).to include('success' => false, 'error' => 'too_large')
  end

  it 'takes the browser open in Now to the address instead of starting another, as the user\'s' do
    allow(MonadicSharedTools::WebAutomation).to receive(:available?).and_return(true)
    live = { id: 'i_browser', kind: 'browser', place: 'current', status: 'open' }
    board = double('board', snapshot: { items: [live] })
    allow(Monadic::Workbench::Board).to receive(:existing).with(session[:chat_id]).and_return(board)
    opener_seen = Queue.new
    expect(opener).not_to receive(:start_browser)
    allow(opener).to receive(:browser_navigate) do |url:|
      opener_seen << [url, Thread.current[:workbench_opener]]
      { success: true }
    end

    host.send(:handle_ws_workbench_open_url, nil, { 'url' => 'https://example.com/next' }, session)

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => true, 'item_id' => 'i_browser')
    expect(opener_seen.pop).to eq(['https://example.com/next', { tab: 'tab-open-url', generation: nil }])
  end

  it 'starts the browser with the browser tools\' own start, on an app object' do
    allow(WebSocketHelper).to receive(:page_browser_host).and_call_original
    built = WebSocketHelper.page_browser_host
    expect(built.ancestors).to include(MonadicApp, MonadicSharedTools::WebAutomation)
    expect(built.new).to respond_to(:start_browser)
  end
end
