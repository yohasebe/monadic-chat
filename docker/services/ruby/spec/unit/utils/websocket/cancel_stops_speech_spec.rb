# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/monadic/utils/websocket"

# Cancel stops speech that is still being made for the reply (the TTS thread
# starts when the text is done), not only the text stream.
RSpec.describe "WebSocketHelper#handle_ws_cancel" do
  let(:handler) { Class.new { include WebSocketHelper }.new }

  before do
    allow(WebSocketHelper).to receive(:send_to_session)
    allow(WebSocketHelper).to receive(:broadcast_to_all)
  end

  it "stops a running TTS thread and tells the tab" do
    tts = Thread.new { sleep }
    handler.instance_variable_set(:@tts_thread, tts)
    allow(handler).to receive(:puts)

    handler.handle_ws_cancel("tab-1")

    expect(tts.join(1)).not_to be_nil
    expect(tts.alive?).to be false
    expect(handler.instance_variable_get(:@tts_thread)).to be_nil
    expect(WebSocketHelper).to have_received(:send_to_session).with({ "type" => "cancel" }.to_json, "tab-1")
  ensure
    tts&.kill
  end

  it "tells every tab when there is no session id, with no TTS running" do
    handler.handle_ws_cancel(nil)
    expect(WebSocketHelper).to have_received(:broadcast_to_all).with({ "type" => "cancel" }.to_json)
  end
end
