# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/utils/websocket'

RSpec.describe 'Opening an address in the chat browser from the page' do
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

  before do
    Thread.current[:websocket_session_id] = 'tab-open-url'
    allow(WebSocketHelper).to receive(:page_browser_host).and_return(double(new: opener))
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

    expect(answer).to eq('type' => 'workbench_open_url', 'success' => true, 'error' => nil)
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

  it 'starts the browser with the browser tools\' own start, on an app object' do
    allow(WebSocketHelper).to receive(:page_browser_host).and_call_original
    built = WebSocketHelper.page_browser_host
    expect(built.ancestors).to include(MonadicApp, MonadicSharedTools::WebAutomation)
    expect(built.new).to respond_to(:start_browser)
  end
end
